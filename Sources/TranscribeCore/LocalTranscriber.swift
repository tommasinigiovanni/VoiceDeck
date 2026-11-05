import Foundation
import FluidAudio

public enum TranscriptionMode: String, CaseIterable, Sendable {
    case openRouter, local
    public static let localModelID = "nvidia/parakeet-tdt-0.6b-v3 (Core ML)"
    public var modelID: String { self == .local ? Self.localModelID : OpenRouterClient.model }
    public var title: String { self == .local ? "Locale · Parakeet v3" : "OpenRouter · Nemotron 3.5" }
}

public actor LocalTranscriber {
    private var manager: AsrManager?
    public init() {}

    public static func modelsExist(at directory: URL) -> Bool {
        let names = ["Encoder.mlmodelc", "Decoder.mlmodelc", "Preprocessor.mlmodelc", "JointDecisionv3.mlmodelc"]
        return names.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).appendingPathComponent("coremldata.bin").path) }
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent("parakeet_vocab.json").path)
    }

    public func loadModels(from directory: URL? = nil,
                           progress: @escaping @Sendable (Double) async -> Void = { _ in }) async throws {
        if manager != nil { return }
        try Task.checkCancellation()
        let models: AsrModels
        let cached = AsrModels.defaultCacheDirectory(for: .v3)
        let available = directory ?? (Self.modelsExist(at: cached) ? cached : nil)
        if let directory = available {
            // Strictly local loader: a selected folder never triggers an implicit network request.
            guard Self.modelsExist(at: directory) else {
                throw TranscribeError.message("La cartella deve contenere Parakeet v3 in Core ML: Encoder, Decoder, Preprocessor, JointDecisionv3 e parakeet_vocab.json. I file GGUF o ONNX di altre app richiedono un runtime diverso.")
            }
            models = try AsrModels.loadLocal(from: directory, version: .v3)
        } else {
            models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: { update in
                Task { await progress(update.fractionCompleted) }
            })
        }
        try Task.checkCancellation()
        let asr = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1))
        try await asr.loadModels(models)
        manager = asr
    }

    public func transcribe(chunk: AudioChunk, language: String = "") async throws -> TranscriptionResult {
        guard let manager else { throw TranscribeError.message("Il modello locale non è ancora pronto.") }
        try Task.checkCancellation()
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(chunk.url, decoderState: &decoderState, language: Language(rawValue: language))
        try Task.checkCancellation()
        let words = buildWordTimings(from: result.tokenTimings ?? [])
        let segments = words.map { word in
            TranscriptSegment(start: chunk.offset + max(0, min(chunk.duration, word.startTime)),
                              end: chunk.offset + max(0, min(chunk.duration, word.endTime)),
                              text: word.word, chunkIndex: chunk.index)
        }
        if segments.isEmpty, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TranscriptionResult(segments: [.init(start: nil, end: nil, text: result.text, chunkIndex: chunk.index)], cost: 0,
                                       warnings: ["Parakeet non ha restituito timestamp per questa parte."])
        }
        return TranscriptionResult(segments: segments, cost: 0, warnings: [])
    }

    public func cleanup() async {
        await manager?.cleanup(); manager = nil
    }
}
