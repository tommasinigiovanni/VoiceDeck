import Foundation
import TranscribeCore

@main
struct TranscribeCheck {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let path = arguments.first, !path.hasPrefix("--") else {
            print("Uso: TranscribeCheck /percorso/audio [--speakers] [--models /cartella/speaker] [--transcribe-local] [--asr-models /cartella/parakeet] [--prefer-gpu]")
            exit(2)
        }
        do {
            let prepared = try await AudioPreparer().prepare(url: URL(fileURLWithPath: path))
            defer { prepared.cleanup() }
            print("Audio: \(Timecode.display(prepared.duration)), \(prepared.chunks.count) parti")
            for chunk in prepared.chunks {
                print("Parte \(chunk.index + 1): offset \(chunk.offset), durata \(chunk.duration), \(chunk.byteCount) byte")
            }
            var intervals: [SpeakerInterval] = []
            if arguments.contains("--speakers") {
                let modelIndex = arguments.firstIndex(of: "--models")
                let directory = modelIndex.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
                intervals = try await LocalDiarizer().analyze(prepared, localModelDirectory: directory) { _, _ in }
                for interval in intervals { print("\(Timecode.display(interval.start)) - \(Timecode.display(interval.end))  \(interval.speaker)") }
                print("Speaker: \(Set(intervals.map(\.speaker)).count), intervalli: \(intervals.count)")
            }
            if arguments.contains("--transcribe-local") {
                let index = arguments.firstIndex(of: "--asr-models")
                let directory = index.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
                let local = LocalTranscriber()
                try await local.loadModels(from: directory, preferGPU: arguments.contains("--prefer-gpu"))
                print("Esecuzione: \(await local.executionDescription)")
                var document = TranscriptDocument(title: URL(fileURLWithPath: path).lastPathComponent, sourcePath: path, duration: prepared.duration)
                document.model = TranscriptionMode.localModelID
                document.totalChunks = prepared.chunks.count
                for chunk in prepared.chunks {
                    let result = try await local.transcribe(chunk: chunk)
                    document.segments += intervals.isEmpty ? SpeakerAligner.coalesce(result.segments) : SpeakerAligner.align(result.segments, intervals: intervals)
                    document.completedChunks += 1
                }
                await local.cleanup()
                document.isComplete = true
                print(document.textExport())
                if let i = arguments.firstIndex(of: "--output"), i + 1 < arguments.count {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(document).write(to: URL(fileURLWithPath: arguments[i + 1]), options: .atomic)
                }
            }
        } catch { print("Errore: \(error.localizedDescription)"); exit(1) }
    }
}
