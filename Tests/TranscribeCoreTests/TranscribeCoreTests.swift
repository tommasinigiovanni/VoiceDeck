import XCTest
import AVFoundation
@testable import TranscribeCore

final class TranscribeCoreTests: XCTestCase {
    private func chunk(index: Int = 0, offset: Double = 0, duration: Double = 480) -> AudioChunk {
        AudioChunk(index: index, url: URL(fileURLWithPath: "/tmp/unused.wav"), offset: offset, duration: duration, byteCount: 0)
    }

    func testWordParsingKeepsTimesAndGlobalOffsets() throws {
        let json = #"{"text":"Ciao Marco","words":[{"word":"Ciao","start":1,"end":1.4},{"word":"Marco","start":1.5,"end":2}],"usage":{"cost":0.01}}"#
        let result = try TranscriptParser.parse(Data(json.utf8), chunk: chunk(index: 2, offset: 960))
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].start, 961)
        XCTAssertEqual(result.segments[1].end, 962)
        XCTAssertEqual(result.cost, 0.01)
        XCTAssertNil(result.segments[0].speakerID)
    }

    func testArchivePreservesLocalModeForResume() throws {
        var doc = TranscriptDocument(title: "Locale", sourcePath: "/tmp/audio.wav", duration: 960)
        doc.model = TranscriptionMode.localModelID; doc.completedChunks = 1; doc.totalChunks = 2
        doc.usesLocalDiarization = true
        let decoded = try JSONDecoder().decode(TranscriptDocument.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(decoded.model, TranscriptionMode.local.modelID)
        XCTAssertEqual(decoded.completedChunks, 1)
        XCTAssertFalse(decoded.isComplete)
        XCTAssertNotEqual(TranscriptionMode.local.modelID, TranscriptionMode.openRouter.modelID)
    }

    func testEditingPreservesAudioAlignmentAndOriginalText() throws {
        var document = TranscriptDocument(title: "Intervista", sourcePath: "audio.m4a", duration: 10)
        let segment = TranscriptSegment(start: 2.5, end: 5.2, text: "Una frase sbaliata.", speakerID: "A", chunkIndex: 0)
        document.segments = [segment]
        try document.editSegment(id: segment.id, text: "Una frase corretta.", speakerID: "B")
        try document.editSegment(id: segment.id, text: "Una frase ancora più precisa.", speakerID: "B")
        let saved = try JSONDecoder().decode(TranscriptDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(saved.segments[0].start, 2.5); XCTAssertEqual(saved.segments[0].end, 5.2)
        XCTAssertEqual(saved.segments[0].originalText, "Una frase sbaliata.")
        XCTAssertEqual(saved.segments[0].speakerID, "B")
        XCTAssertNotNil(saved.segments[0].editedAt)
        XCTAssertTrue(saved.srtExport().contains("Una frase ancora più precisa."))
    }

    func testSpeakerIDsNeverImplicitlyMergeAcrossRequests() throws {
        let json = #"{"segments":[{"text":"Ciao","start":0,"end":1,"speaker":0}]}"#
        let a = try TranscriptParser.parse(Data(json.utf8), chunk: chunk())
        let b = try TranscriptParser.parse(Data(json.utf8), chunk: chunk(index: 1, offset: 480))
        XCTAssertNotEqual(a.segments[0].speakerID, b.segments[0].speakerID)
    }

    func testTextOnlyDoesNotInventTimestampsOrSpeakers() throws {
        let plain = try TranscriptParser.parse(Data(#"{"text":"Ciao a tutti"}"#.utf8), chunk: chunk())
        XCTAssertNil(plain.segments[0].start); XCTAssertNil(plain.segments[0].speakerID)
        let tags = try TranscriptParser.parse(Data(#"{"text":"<spk:0>ciao <spk:1>buongiorno"}"#.utf8), chunk: chunk())
        XCTAssertEqual(tags.segments.count, 2); XCTAssertNil(tags.segments[1].start)
        XCTAssertEqual(tags.segments[1].speakerID, "P1 · Speaker 1")
    }

    func testLocalTimelineSplitsWordsAtSpeakerChangeAcrossUploadParts() {
        let intervals = [SpeakerInterval(speaker: "Speaker 1", start: 0, end: 1.5), SpeakerInterval(speaker: "Speaker 2", start: 1.5, end: 4),
                         SpeakerInterval(speaker: "Speaker 1", start: 481, end: 482)]
        let words = [TranscriptSegment(start: 0, end: 0.5, text: "Ciao", chunkIndex: 0),
                     TranscriptSegment(start: 0.6, end: 1, text: "Marco.", chunkIndex: 0),
                     TranscriptSegment(start: 1.6, end: 2, text: "Buongiorno!", chunkIndex: 0),
                     TranscriptSegment(start: 481, end: 482, text: "Di nuovo.", chunkIndex: 1)]
        let result = SpeakerAligner.align(words, intervals: intervals)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].text, "Ciao Marco.")
        XCTAssertEqual(result.map(\.speakerID), ["Speaker 1", "Speaker 2", "Speaker 1"])
    }

    func testSRTUsesOnlyRealTimesAndHandlesMillisecondCarry() {
        var doc = TranscriptDocument(title: "Intervista", sourcePath: "", duration: 60)
        doc.segments = [.init(start: 0, end: 1.9999, text: "Ciao", speakerID: "A", chunkIndex: 0),
                        .init(start: nil, end: nil, text: "Nessun tempo", chunkIndex: 0)]
        doc.speakerNames["A"] = "Giulia"
        XCTAssertTrue(doc.srtExport().contains("00:00:00,000 --> 00:00:02,000\nGiulia: Ciao"))
        XCTAssertFalse(doc.srtExport().contains("Nessun tempo"))
    }

    func testSpeakerAlignmentHandlesOverlappingWordOrder() {
        let words = [TranscriptSegment(start: 5, end: 6, text: "Secondo", chunkIndex: 0),
                     TranscriptSegment(start: 1, end: 2, text: "Primo", chunkIndex: 0)]
        let timeline = [SpeakerInterval(speaker: "A", start: 0, end: 3), SpeakerInterval(speaker: "B", start: 4, end: 8)]
        XCTAssertEqual(SpeakerAligner.align(words, intervals: timeline).map(\.speakerID), ["B", "A"])
    }

    func testRequestBudgetIncludesBase64Overhead() throws {
        let frames = AudioLimits.maximumFrames(seconds: 3600)
        let wav = WAV.encode(pcm: Data(repeating: 255, count: frames * 2))
        let request = try JSONSerialization.data(withJSONObject: ["model": OpenRouterClient.model,
            "input_audio": ["data": wav.base64EncodedString(), "format": "wav"], "response_format": "verbose_json"], options: [.withoutEscapingSlashes])
        XCTAssertLessThanOrEqual(wav.count, AudioLimits.maximumWAVBytes)
        XCTAssertLessThan(request.count, AudioLimits.maximumRequestBytes)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .utf8), "RIFF")
    }

    func testLargeStereoSourceIsSplitWithoutMissingOrDuplicateFrames() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("large.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for c in 0..<2 { for i in 0..<48_000 { buffer.floatChannelData![c][i] = i < 40_000 ? sin(Float(i) * 0.04) * 0.15 : 0 } }
        for _ in 0..<140 { try file!.write(from: buffer) }
        file = nil
        XCTAssertGreaterThan((try source.resourceValues(forKeys: [.fileSizeKey])).fileSize!, 25_000_000)
        let prepared = try await AudioPreparer().prepare(url: source, chunkSeconds: 60)
        defer { prepared.cleanup() }
        XCTAssertGreaterThan(prepared.chunks.count, 1)
        XCTAssertEqual(prepared.duration, 140, accuracy: 0.002)
        var next = 0.0
        for chunk in prepared.chunks {
            XCTAssertEqual(chunk.offset, next, accuracy: 0.00001)
            XCTAssertLessThanOrEqual(chunk.byteCount, AudioLimits.maximumWAVBytes)
            let bytes = try Data(contentsOf: chunk.url)
            XCTAssertEqual(bytes.count, 44 + Int((chunk.duration * 16000).rounded()) * 2)
            next += chunk.duration
        }
        XCTAssertEqual(next, prepared.duration, accuracy: 0.00001)
    }

    func testPreCancelledJobStopsBeforeReading() async throws {
        let task = Task { () -> PreparedAudio in
            try Task.checkCancellation()
            return try await AudioPreparer().prepare(url: URL(fileURLWithPath: "/tmp/nonexistent-audio"))
        }
        task.cancel()
        do { let audio = try await task.value; audio.cleanup(); XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }

    func testTinyFinalTailIsKeptWithoutAnotherRequest() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        var pcm = Data()
        for _ in 0..<160_800 { pcm.append(contentsOf: [0x10, 0x27]) }
        try WAV.encode(pcm: pcm).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let audio = try await AudioPreparer().prepare(url: source, chunkSeconds: 10)
        defer { audio.cleanup() }
        XCTAssertEqual(audio.chunks.count, 1)
        XCTAssertEqual(audio.duration, 10.05, accuracy: 0.0001)
        XCTAssertEqual(audio.chunks[0].byteCount, pcm.count + 44)
    }
}
