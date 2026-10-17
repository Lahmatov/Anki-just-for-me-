import XCTest
@testable import AJFMCore

final class LessonSpeechTests: XCTestCase {

    func testWordsCountInAnotherForm() {
        let result = LessonSpeech.check(transcript: "Ontem comi bacalhau no talho",
                                        terms: ["comer", "o talho", "a chávena"], language: .portuguese)
        XCTAssertEqual(result.used, ["comer", "o talho"])
        XCTAssertEqual(result.unused, ["a chávena"])
        XCTAssertEqual(result.coverage, 2.0 / 3, accuracy: 0.0001)
    }

    /// «tenho» по началу слова за «ter» не узнать — помогает спряжение.
    func testIrregularVerbFormsAreRecognised() {
        let result = LessonSpeech.check(transcript: "Tenho saudades de casa. Fui ao mercado.",
                                        terms: ["ter saudades", "ir"], language: .portuguese)
        XCTAssertEqual(result.used, ["ter saudades", "ir"])
    }

    func testItalianPastParticipleAndReflexive() {
        let result = LessonSpeech.check(transcript: "Ieri ho fatto la spesa e mi sono alzato presto",
                                        terms: ["fare la spesa", "alzarsi"], language: .italian)
        XCTAssertEqual(result.used, ["fare la spesa", "alzarsi"])
    }

    func testAccentsDoNotMatter() {
        let result = LessonSpeech.check(transcript: "uma chavena de cafe",
                                        terms: ["a chávena"], language: .portuguese)
        XCTAssertEqual(result.used, ["a chávena"])
    }

    func testAllWordsOfAPhraseAreNeeded() {
        let result = LessonSpeech.check(transcript: "I want to book a table",
                                        terms: ["book a flight"], language: .english)
        XCTAssertEqual(result.unused, ["book a flight"])
    }

    func testEmptyTranscriptUsesNothing() {
        let result = LessonSpeech.check(transcript: "", terms: ["casa"], language: .italian)
        XCTAssertEqual(result.used, [])
        XCTAssertEqual(result.coverage, 0)
    }

    func testNoTermsMeansZeroCoverageNotNaN() {
        XCTAssertEqual(LessonSpeech.check(transcript: "ciao", terms: [], language: .italian).coverage, 0)
    }

    func testDuplicateTermsCountOnce() {
        let result = LessonSpeech.check(transcript: "casa", terms: ["casa", "Casa"], language: .italian)
        XCTAssertEqual(result.used, ["casa"])
        XCTAssertTrue(result.unused.isEmpty)
    }
}
