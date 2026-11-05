import Foundation
import FluidAudio

public struct SpeakerInterval: Codable, Sendable, Equatable {
    public var speaker: String
    public var start: Double
    public var end: Double
    public init(speaker: String, start: Double, end: Double) { self.speaker = speaker; self.start = start; self.end = end }
}

/// Owns one stateful diarizer across all upload chunks, preserving arrival-order speaker slots.
public actor LocalDiarizer {
    public init() {}
    public func analyze(_ audio: PreparedAudio, cacheDirectory: URL? = nil, localModelDirectory: URL? = nil,
                        preferGPU: Bool = false,
                        progress: @Sendable (Double, String) async -> Void) async throws -> [SpeakerInterval] {
        try await ResourceGovernor.checkpoint()
        await progress(0, "Preparazione modello speaker (circa 190 MB al primo utilizzo)…")
        let config = Nemotron3Config.fast128
        let plan = ExecutionPlan.choose(preferGPU: preferGPU, resources: .current)
        let models: Nemotron3Models
        if let localModelDirectory { models = try await Nemotron3Models.load(config: config, directory: localModelDirectory, computeUnits: plan.otherUnits) }
        else { models = try await Nemotron3Models.loadFromHuggingFace(config: config, cacheDirectory: cacheDirectory, computeUnits: plan.otherUnits) }
        try Task.checkCancellation()
        let diarizer = Nemotron3Diarizer(config: config, models: models)
        var probabilities: [Float] = []
        var frames = 0
        var consumedSamples = 0
        for chunk in audio.chunks {
            let handle = try FileHandle(forReadingFrom: chunk.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: 44) // Our canonical WAV has a fixed 44-byte PCM header.
            while let data = try handle.read(upToCount: 32_000), !data.isEmpty {
                try Task.checkCancellation()
                let fraction = min(0.99, Double(consumedSamples) / 16_000 / audio.duration)
                try await ResourceGovernor.checkpoint { message in
                    await progress(fraction, message)
                }
                try autoreleasepool {
                    let samples = data.withUnsafeBytes { raw -> [Float] in
                        let bytes = raw.bindMemory(to: UInt8.self)
                        return stride(from: 0, to: bytes.count - 1, by: 2).map {
                            Float(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)) / 32768
                        }
                    }
                    diarizer.appendAudio(samples)
                    for result in try diarizer.processBufferedAudio() {
                        probabilities.append(contentsOf: result.probabilities); frames += result.frameCount
                    }
                    consumedSamples += samples.count
                }
                await progress(min(0.99, Double(consumedSamples) / 16_000 / audio.duration), "Riconoscimento degli speaker sul Mac…")
            }
        }
        for result in try diarizer.finishStream() { probabilities.append(contentsOf: result.probabilities); frames += result.frameCount }
        let intervals = Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frames).map {
            SpeakerInterval(speaker: "Speaker \($0.speakerIndex + 1)", start: Double($0.startSeconds), end: Double($0.endSeconds))
        }
        await progress(1, "Speaker analizzati")
        return intervals.sorted { $0.start < $1.start }
    }
}

public enum SpeakerAligner {
    public static func align(_ segments: [TranscriptSegment], intervals: [SpeakerInterval]) -> [TranscriptSegment] {
        let timelines = Dictionary(grouping: intervals, by: \.speaker).mapValues { $0.sorted { $0.end < $1.end } }
        let labeled = segments.map { segment -> TranscriptSegment in
            var item = segment
            // Text-only output has no reliable alignment; preserve it without inventing a speaker.
            guard let start = item.start, let end = item.end, end >= start else { item.speakerID = nil; return item }
            var score: [String: Double] = [:]
            for (speaker, timeline) in timelines {
                // Intervals of one speaker do not overlap. Binary search also handles words
                // returned out of chronological order during overlapping speech.
                var lower = 0, upper = timeline.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if timeline[middle].end < start { lower = middle + 1 } else { upper = middle }
                }
                var i = lower
                while i < timeline.count, timeline[i].start <= max(end, start + 0.02) {
                    let overlap = max(0, min(max(end, start + 0.02), timeline[i].end) - max(start, timeline[i].start))
                    if overlap > 0 { score[speaker, default: 0] += overlap }
                    i += 1
                }
            }
            item.speakerID = score.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
            return item
        }
        return coalesce(labeled)
    }

    public static func coalesce(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for item in segments {
            if let last = result.last, last.speakerID == item.speakerID, last.chunkIndex == item.chunkIndex,
               let end = last.end, let start = item.start, start >= (last.start ?? 0), start - end < 1.5,
               last.text.count + item.text.count < 600 {
                let i = result.count - 1
                let punctuation = item.text.first.map { ".,!?;:…".contains($0) } ?? false
                result[i].text += (punctuation || item.text.hasPrefix(" ") ? "" : " ") + item.text
                result[i].end = max(end, item.end ?? end)
            } else { result.append(item) }
        }
        return result
    }
}
