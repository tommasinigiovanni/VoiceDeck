import XCTest
@testable import TranscribeCore

final class VocabularyAndResourcesTests: XCTestCase {
    func testNamesAndCompanySpellingWithPunctuation() {
        let entries = [VocabularyEntry(spelling: "evoseed", aliases: ["Evo seed"]),
                       VocabularyEntry(spelling: "Giovanni Tommasini", aliases: ["Giovani Tommasini"])]
        XCTAssertEqual(PersonalVocabulary.correct("Giovani Tommasini lavora in Evo seed. EVOSEED!", entries: entries),
                       "Giovanni Tommasini lavora in evoseed. evoseed!")
    }
    func testUnicodeWordsAndRegexCharactersAreNotCorrupted() {
        let entries = [VocabularyEntry(spelling: "AI", aliases: ["ai"]), VocabularyEntry(spelling: "C++", aliases: ["C più più"])]
        XCTAssertEqual(PersonalVocabulary.correct("ormai, naïve, ai, C più più e C++.", entries: entries), "ormai, naïve, AI, C++ e C++.")
    }
    func testLongestVariantWinsAndReplacementsDoNotCascade() {
        let entries = [VocabularyEntry(spelling: "AI Fabric", aliases: ["a i fabric"]),
                       VocabularyEntry(spelling: "Intelligenza", aliases: ["AI"])]
        XCTAssertEqual(PersonalVocabulary.correct("a i fabric", entries: entries), "AI Fabric")
    }
    func testConflictingAliasUsesFirstEntryAndEmptyDictionaryDoesNothing() {
        let entries = [VocabularyEntry(spelling: "Alfa", aliases: ["acme"]), VocabularyEntry(spelling: "Beta", aliases: ["acme"])]
        XCTAssertEqual(PersonalVocabulary.correct("Acme", entries: entries), "Alfa")
        XCTAssertEqual(PersonalVocabulary.correct("Nessuna modifica", entries: []), "Nessuna modifica")
    }
    func testApplyingDictionaryPreservesOriginalAndTiming() throws {
        var doc = TranscriptDocument(title: "Esempio", sourcePath: "/tmp/example.wav", duration: 3)
        let segment = TranscriptSegment(start: 1, end: 2, text: "Evo seed", speakerID: "Speaker 1", chunkIndex: 0)
        doc.segments = [segment]
        let text = PersonalVocabulary.correct(segment.text, entries: [.init(spelling: "evoseed", aliases: ["Evo seed"])])
        try doc.editSegment(id: segment.id, text: text, speakerID: segment.speakerID)
        XCTAssertEqual(doc.segments[0].originalText, "Evo seed")
        XCTAssertEqual(doc.segments[0].start, 1); XCTAssertEqual(doc.segments[0].end, 2)
        XCTAssertEqual(doc.segments[0].speakerID, "Speaker 1")
    }
    func testEfficientDefaultUsesNeuralEngineAndGPURequiresExplicitPreference() {
        let normal = ResourceSnapshot(hasNeuralEngine: true, lowPower: false, thermalLevel: 0, memoryPressure: 0)
        let efficient = ExecutionPlan.choose(preferGPU: false, resources: normal)
        XCTAssertFalse(efficient.usesGPU); XCTAssertEqual(efficient.encoderUnits, .cpuAndNeuralEngine)
        XCTAssertTrue(ExecutionPlan.choose(preferGPU: true, resources: normal).usesGPU)
    }
    func testPowerHeatAndMemoryOverrideGPUPreference() {
        for state in [ResourceSnapshot(hasNeuralEngine: true, lowPower: true, thermalLevel: 0, memoryPressure: 0),
                      ResourceSnapshot(hasNeuralEngine: true, lowPower: false, thermalLevel: 2, memoryPressure: 0),
                      ResourceSnapshot(hasNeuralEngine: true, lowPower: false, thermalLevel: 0, memoryPressure: 1)] {
            XCTAssertFalse(ExecutionPlan.choose(preferGPU: true, resources: state).usesGPU)
        }
        let fallback = ExecutionPlan.choose(preferGPU: false, resources: .init(hasNeuralEngine: false, lowPower: false, thermalLevel: 0, memoryPressure: 0))
        XCTAssertEqual(fallback.encoderUnits, .cpuOnly)
    }
}
