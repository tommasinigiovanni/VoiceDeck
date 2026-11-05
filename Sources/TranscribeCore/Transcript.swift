import Foundation

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Double?
    public var end: Double?
    public var text: String
    public var speakerID: String?
    public var chunkIndex: Int
    public var originalText: String? = nil
    public var editedAt: Date? = nil

    public init(id: UUID = UUID(), start: Double?, end: Double?, text: String, speakerID: String? = nil, chunkIndex: Int) {
        self.id = id; self.start = start; self.end = end; self.text = text
        self.speakerID = speakerID; self.chunkIndex = chunkIndex
    }
}

public struct TranscriptDocument: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var createdAt = Date()
    public var sourcePath: String
    public var duration: Double
    public var model = OpenRouterClient.model
    public var segments: [TranscriptSegment] = []
    public var speakerNames: [String: String] = [:]
    public var completedChunks = 0
    public var totalChunks = 0
    public var cost: Double = 0
    public var warnings: [String] = []
    public var isComplete = false
    public var usesLocalDiarization = true
    public var language = ""
    public var chunkSeconds = AudioLimits.defaultChunkSeconds
    public var sourceBytes: Int64 = 0
    public var sourceModifiedAt: Date? = nil

    public init(title: String, sourcePath: String, duration: Double) {
        self.title = title; self.sourcePath = sourcePath; self.duration = duration
    }

    public var speakerIDs: [String] {
        var seen = Set<String>()
        return segments.compactMap(\.speakerID).filter { seen.insert($0).inserted }
    }

    public mutating func editSegment(id: UUID, text: String, speakerID: String?) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TranscribeError.message("Il testo del passaggio non può essere vuoto.") }
        guard let index = segments.firstIndex(where: { $0.id == id }) else { throw TranscribeError.message("Passaggio non trovato.") }
        if segments[index].originalText == nil { segments[index].originalText = segments[index].text }
        segments[index].text = value; segments[index].speakerID = speakerID; segments[index].editedAt = Date()
    }

    public func speakerName(_ id: String?) -> String {
        guard let id else { return "Speaker non disponibile" }
        return speakerNames[id] ?? id
    }

    public func textExport(markdown: Bool = false) -> String {
        var lines = [markdown ? "# \(title)" : title, ""]
        if !isComplete { lines += ["Trascrizione parziale (\(completedChunks)/\(totalChunks) parti).", ""] }
        for warning in warnings { lines += [markdown ? "> \(warning)" : warning, ""] }
        for segment in segments {
            let stamp = segment.start.map { "[\(Timecode.display($0))] " } ?? ""
            let name = speakerName(segment.speakerID)
            lines += [markdown ? "\(stamp)**\(name)**" : "\(stamp)\(name)", segment.text, ""]
        }
        return lines.joined(separator: "\n")
    }

    public func srtExport() -> String {
        segments.compactMap { segment -> (TranscriptSegment, Double, Double)? in
            guard let start = segment.start, let end = segment.end, end > start else { return nil }
            return (segment, start, end)
        }.enumerated().map { index, item in
            let (segment, start, end) = item
            let prefix = segment.speakerID.map { "\(speakerName($0)): " } ?? ""
            return "\(index + 1)\n\(Timecode.srt(start)) --> \(Timecode.srt(end))\n\(prefix)\(segment.text)\n"
        }.joined(separator: "\n")
    }
}

public enum Timecode {
    public static func display(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
    public static func srt(_ seconds: Double) -> String {
        let value = max(0, Int(((seconds.isFinite ? seconds : 0) * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", value / 3_600_000, (value / 60_000) % 60, (value / 1000) % 60, value % 1000)
    }
}

public enum TranscribeError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
