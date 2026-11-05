import AVFoundation
import Foundation

public struct AudioChunk: Identifiable, Sendable {
    public let index: Int
    public let url: URL
    public let offset: Double
    public let duration: Double
    public let byteCount: Int
    public var id: Int { index }
    public init(index: Int, url: URL, offset: Double, duration: Double, byteCount: Int) {
        self.index = index; self.url = url; self.offset = offset; self.duration = duration; self.byteCount = byteCount
    }
}

public struct PreparedAudio: Sendable {
    public let directory: URL
    public let chunks: [AudioChunk]
    public let duration: Double
    public func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

public enum AudioLimits {
    public static let sampleRate = 16_000
    // Base64 adds 33%. Keep the *entire JSON request* below the 25 MB cap.
    public static let maximumRequestBytes = 24_500_000
    public static let maximumWAVBytes = 18_000_000
    public static let defaultChunkSeconds = 480
    public static func maximumFrames(seconds: Int) -> Int {
        min(max(10, seconds) * sampleRate, (maximumWAVBytes - 44) / 2)
    }
}

/// Streams the decoded source into bounded PCM buffers; never loads the original file in RAM.
public actor AudioPreparer {
    public init() {}

    public func inspect(url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw TranscribeError.message("Il file non contiene audio leggibile.") }
        return duration
    }

    public func prepare(url: URL, chunkSeconds: Int = AudioLimits.defaultChunkSeconds,
                        progress: @Sendable (Double) async -> Void = { _ in }) async throws -> PreparedAudio {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceDeck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            guard duration.isFinite, duration > 0 else { throw TranscribeError.message("Il file non contiene una registrazione audio valida.") }
            guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: file.processingFormat, to: format),
                  let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000) else {
                throw TranscribeError.message("Formato audio non convertibile da macOS.")
            }
            converter.downmix = true
            let targetBytes = AudioLimits.maximumFrames(seconds: chunkSeconds) * 2
            var buffer = Data()
            buffer.reserveCapacity(targetBytes + 128_000)
            var chunks: [AudioChunk] = []
            var writtenFrames = 0
            var lastProgress = -1.0

            func writeChunk(_ byteCount: Int) throws {
                let pcm = Data(buffer.prefix(byteCount))
                let file = directory.appendingPathComponent(String(format: "part-%04d.wav", chunks.count + 1))
                let wav = WAV.encode(pcm: pcm)
                guard wav.count <= AudioLimits.maximumWAVBytes else { throw TranscribeError.message("La parte audio supera il limite di invio.") }
                try wav.write(to: file, options: .atomic)
                let frames = byteCount / 2
                chunks.append(AudioChunk(index: chunks.count, url: file, offset: Double(writtenFrames) / 16_000,
                                         duration: Double(frames) / 16_000, byteCount: wav.count))
                writtenFrames += frames
                buffer = Data(buffer.dropFirst(byteCount))
            }

            var finished = false
            while !finished {
                try Task.checkCancellation()
                try autoreleasepool {
                    var conversionError: NSError?
                    var readError: Error?
                    let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
                        guard file.framePosition < file.length else { inputStatus.pointee = .endOfStream; return nil }
                        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: max(1, requested)) else {
                            inputStatus.pointee = .endOfStream
                            readError = TranscribeError.message("Memoria insufficiente per leggere l’audio.")
                            return nil
                        }
                        do {
                            try file.read(into: input, frameCount: requested)
                            inputStatus.pointee = input.frameLength > 0 ? .haveData : .endOfStream
                            return input.frameLength > 0 ? input : nil
                        } catch { readError = error; inputStatus.pointee = .endOfStream; return nil }
                    }
                    if let readError { throw readError }
                    if status == .error { throw conversionError ?? TranscribeError.message("Errore nella conversione audio.") }
                    if output.frameLength > 0, let samples = output.int16ChannelData {
                        buffer.append(Data(bytes: samples[0], count: Int(output.frameLength) * 2))
                    }
                    while buffer.count >= targetBytes {
                        try writeChunk(WAV.quietBoundary(in: buffer, targetBytes: targetBytes))
                    }
                    finished = status == .endOfStream
                }
                let fraction = min(0.99, (Double(writtenFrames) + Double(buffer.count / 2)) / 16_000 / duration)
                if fraction - lastProgress > 0.01 { lastProgress = fraction; await progress(fraction) }
            }
            try Task.checkCancellation()
            if !buffer.isEmpty {
                // Keep a sub-half-second tail with the preceding part. Tiny standalone
                // requests are rejected by many speech engines and add no useful context.
                if buffer.count < 16_000, let previous = chunks.last,
                   previous.byteCount + buffer.count <= AudioLimits.maximumWAVBytes {
                    let previousWAV = try Data(contentsOf: previous.url)
                    var pcm = Data(previousWAV.dropFirst(44)); pcm.append(buffer)
                    let wav = WAV.encode(pcm: pcm); try wav.write(to: previous.url, options: .atomic)
                    let tailFrames = buffer.count / 2
                    chunks[chunks.count - 1] = AudioChunk(index: previous.index, url: previous.url, offset: previous.offset,
                        duration: previous.duration + Double(tailFrames) / 16_000, byteCount: wav.count)
                    writtenFrames += tailFrames; buffer.removeAll()
                } else { try writeChunk(buffer.count) }
            }
            guard !chunks.isEmpty else { throw TranscribeError.message("L’audio è vuoto.") }
            await progress(1)
            return PreparedAudio(directory: directory, chunks: chunks, duration: Double(writtenFrames) / 16_000)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

public enum WAV {
    public static func encode(pcm: Data) -> Data {
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        append(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(16_000)); append(UInt32(32_000))
        append(UInt16(2)); append(UInt16(16)); data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }

    /// Prefer a quiet 20 ms frame in the last eight seconds; no overlap or discarded samples.
    public static func quietBoundary(in data: Data, targetBytes: Int) -> Int {
        let target = min(targetBytes, data.count) / 2
        let window = 320
        let lower = max(window, target - 8 * 16_000)
        guard target > window, lower < target else { return target * 2 }
        return data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var best = target, bestEnergy = Double.greatestFiniteMagnitude
            var frame = target - window
            while frame >= lower {
                var energy = 0.0
                for i in frame..<(frame + window) {
                    let sample = Double(Int16(bitPattern: UInt16(bytes[2 * i]) | UInt16(bytes[2 * i + 1]) << 8))
                    energy += sample * sample
                }
                energy /= Double(window)
                if energy < bestEnergy { bestEnergy = energy; best = frame + window / 2 }
                if energy < 40 * 40 { break }
                frame -= window
            }
            // Do not cut early if no quiet region exists.
            return bestEnergy < 600 * 600 ? best * 2 : target * 2
        }
    }
}
