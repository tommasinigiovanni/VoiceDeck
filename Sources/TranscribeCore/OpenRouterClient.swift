import Foundation

public struct ProviderCapability: Sendable {
    public let name: String
    public let tag: String
    public let supportsDiarization: Bool
}

public struct TranscriptionResult: Sendable {
    public let segments: [TranscriptSegment]
    public let cost: Double
    public let warnings: [String]
}

public struct OpenRouterClient: Sendable {
    public static let model = "nvidia/nemotron-3.5-transcribe"
    public let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    public init(apiKey: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session; self.baseURL = baseURL
    }

    public func capabilities() async throws -> [ProviderCapability] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models/\(Self.model)/endpoints"))
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let object = root?["data"] as? [String: Any]
        return (object?["endpoints"] as? [[String: Any]] ?? []).map {
            ProviderCapability(name: $0["provider_name"] as? String ?? "Provider", tag: $0["tag"] as? String ?? "",
                               supportsDiarization: $0["supports_diarization"] as? Bool ?? false)
        }
    }

    public func transcribe(chunk: AudioChunk, language: String = "", model: String = Self.model,
                           providerOptions: [String: [String: JSONValue]] = [:]) async throws -> TranscriptionResult {
        guard !apiKey.isEmpty else { throw TranscribeError.message("Inserisci la chiave API OpenRouter nelle impostazioni.") }
        let audio = try Data(contentsOf: chunk.url, options: .mappedIfSafe)
        guard audio.count <= AudioLimits.maximumWAVBytes else { throw TranscribeError.message("Parte audio troppo grande: prepara nuovamente il file.") }
        var payload: [String: Any] = [
            "model": model, "input_audio": ["data": audio.base64EncodedString(), "format": "wav"],
            "response_format": "verbose_json", "timestamp_granularities": ["segment", "word"]
        ]
        if !language.isEmpty { payload["language"] = language }
        if !providerOptions.isEmpty {
            let encoder = JSONEncoder()
            let options = try JSONSerialization.jsonObject(with: encoder.encode(providerOptions))
            payload["provider"] = ["options": options]
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
        guard body.count < AudioLimits.maximumRequestBytes else { throw TranscribeError.message("La richiesta supera il limite di sicurezza di 24,5 MB.") }
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VoiceDeck for macOS", forHTTPHeaderField: "X-OpenRouter-Title")
        // Retry rate limits and transient upstream failures only. Completed parts are checkpointed by the caller.
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, ([429, 502, 503, 504, 524, 529].contains(http.statusCode)), attempt < 2 {
                let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? pow(2, Double(attempt + 1))
                try await Task.sleep(nanoseconds: UInt64(min(30, max(1, retry)) * 1_000_000_000))
                continue
            }
            try Self.check(response, data: data)
            return try TranscriptParser.parse(data, chunk: chunk)
        }
        throw TranscribeError.message("OpenRouter non è raggiungibile. Riprova tra poco.")
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw TranscribeError.message("Risposta del server non valida.") }
        guard (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = root?["error"] as? [String: Any]
            let detail = error?["message"] as? String ?? root?["message"] as? String ?? ""
            let hint: String
            switch http.statusCode {
            case 401: hint = "Chiave API OpenRouter non valida. Controllala nelle impostazioni."
            case 402: hint = "Credito OpenRouter insufficiente."
            case 413: hint = "Audio rifiutato per dimensione. Riduci la durata delle parti nelle impostazioni e reimporta il file."
            case 400: hint = "Il provider ha rifiutato la richiesta o il formato verbose_json."
            case 429: hint = "Limite di richieste raggiunto. Riprova tra poco."
            default: hint = "Errore OpenRouter (HTTP \(http.statusCode))."
            }
            throw TranscribeError.message(hint + (detail.isEmpty ? "" : "\n\(String(detail.prefix(600)))"))
        }
    }
}

public enum JSONValue: Codable, Sendable {
    case bool(Bool), string(String), number(Double), object([String: JSONValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .bool(let v): try c.encode(v); case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v); case .object(let v): try c.encode(v) }
    }
}

public enum TranscriptParser {
    public static func parse(_ data: Data, chunk: AudioChunk) throws -> TranscriptionResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscribeError.message("OpenRouter ha restituito un JSON non valido.")
        }
        if let error = root["error"] { throw TranscribeError.message("Errore del provider: \(error)") }
        let words = root["words"] as? [[String: Any]] ?? []
        let raw = root["segments"] as? [[String: Any]] ?? []
        var segments: [TranscriptSegment] = []
        // Word labels take precedence when phrase-level segments have no speaker boundaries.
        if !words.isEmpty {
            for word in words {
                guard let text = word["word"] as? String ?? word["text"] as? String, !text.isEmpty else { continue }
                let label = scoped(speaker(word["speaker"]), chunk: chunk.index)
                let times = timestamps(word, chunk: chunk)
                segments.append(TranscriptSegment(start: times.0, end: times.1, text: text, speakerID: label, chunkIndex: chunk.index))
            }
        } else {
            for item in raw {
                guard let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let times = timestamps(item, chunk: chunk)
                segments.append(TranscriptSegment(start: times.0, end: times.1, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   speakerID: scoped(speaker(item["speaker"]), chunk: chunk.index), chunkIndex: chunk.index))
            }
        }
        let text = (root["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if segments.isEmpty, !text.isEmpty {
            let tagged = parseSpeakerTags(text, chunkIndex: chunk.index)
            // No fabricated timestamps when the provider returns text only.
            segments = tagged.isEmpty ? [TranscriptSegment(start: nil, end: nil, text: text, chunkIndex: chunk.index)] : tagged
        }
        guard !segments.isEmpty || root["text"] is String else { throw TranscribeError.message("Risposta incompleta per la parte \(chunk.index + 1): manca il testo della trascrizione.") }
        var warnings: [String] = []
        if segments.isEmpty { warnings.append("Nessun parlato restituito dal provider per la parte \(chunk.index + 1).") }
        if words.isEmpty, !segments.isEmpty { warnings.append("Il provider non ha restituito tempi parola per parola. L’attribuzione locale usa i tempi dei segmenti disponibili.") }
        if segments.contains(where: { $0.speakerID == nil }) {
            warnings.append("Il provider non ha fornito tutti gli speaker. I passaggi senza etichetta sono indicati come non disponibili.")
        }
        if segments.contains(where: { $0.start == nil }) { warnings.append("Alcuni passaggi non hanno timestamp forniti dal modello.") }
        let usage = root["usage"] as? [String: Any]
        return TranscriptionResult(segments: segments, cost: (usage?["cost"] as? NSNumber)?.doubleValue ?? 0, warnings: warnings)
    }

    private static func speaker(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
    private static func scoped(_ speaker: String?, chunk: Int) -> String? { speaker.map { "P\(chunk + 1) · Speaker \($0)" } }
    private static func timestamps(_ item: [String: Any], chunk: AudioChunk) -> (Double?, Double?) {
        func time(_ key: String) -> Double? {
            guard let n = item[key] as? NSNumber, n.doubleValue.isFinite else { return nil }
            return chunk.offset + min(chunk.duration, max(0, n.doubleValue))
        }
        let start = time("start"), end = time("end")
        if let s = start, let e = end, e < s { return (nil, nil) }
        return (start, end)
    }
    private static func parseSpeakerTags(_ text: String, chunkIndex: Int) -> [TranscriptSegment] {
        guard let regex = try? NSRegularExpression(pattern: "<spk:([0-9]+)>") else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.enumerated().compactMap { i, match in
            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let content = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return TranscriptSegment(start: nil, end: nil, text: content,
                                     speakerID: scoped(ns.substring(with: match.range(at: 1)), chunk: chunkIndex), chunkIndex: chunkIndex)
        }
    }
}
