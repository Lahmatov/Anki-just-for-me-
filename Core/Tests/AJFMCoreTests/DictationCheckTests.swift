import XCTest
@testable import AJFMCore

final class DictationCheckTests: XCTestCase {

    private func marks(_ typed: String, _ expected: String) -> [DictationResult.Mark] {
        DictationCheck.check(typed: typed, expected: expected).words.map(\.mark)
    }

    func testCaseAndPunctuationDoNotCount() {
        let result = DictationCheck.check(typed: "ontem comi bacalhau", expected: "Ontem comi bacalhau!")
        XCTAssertTrue(result.isPerfect)
        XCTAssertEqual(result.score, 1)
    }

    /// На слух «está» и «esta» не различить, но писать надо с ударением.
    func testLostAccentIsMarkedButHalfCounted() {
        let result = DictationCheck.check(typed: "Ele esta em casa", expected: "Ele está em casa.")
        XCTAssertEqual(result.words.map(\.mark), [.correct, .accent, .correct, .correct])
        XCTAssertEqual(result.score, 3.5 / 4, accuracy: 0.0001)
        XCTAssertFalse(result.isPerfect)
    }

    func testMissingWordIsShownWhereItBelongs() {
        let result = DictationCheck.check(typed: "Eu como pão", expected: "Eu como o pão")
        XCTAssertEqual(result.words.map(\.mark), [.correct, .correct, .missing, .correct])
        XCTAssertEqual(result.words[2].expected, "o")
    }

    func testExtraWordsCostPoints() {
        let result = DictationCheck.check(typed: "eu como o pão sempre sempre", expected: "eu como o pão")
        XCTAssertEqual(result.words.filter { $0.mark == .extra }.count, 2)
        XCTAssertEqual(result.score, 3.0 / 4, accuracy: 0.0001)
    }

    func testOneLetterOffInALongWordIsATypo() {
        XCTAssertEqual(marks("a cassa", "a casa"), [.correct, .typo])
    }

    func testShortWordsAreNeverTypos() {
        XCTAssertEqual(marks("o pão", "a pão"), [.wrong, .correct])
    }

    func testDifferentWordIsWrong() {
        let result = DictationCheck.check(typed: "vou ao cinema", expected: "vou ao teatro")
        XCTAssertEqual(result.words.map(\.mark), [.correct, .correct, .wrong])
        XCTAssertEqual(result.words[2].typed, "cinema")
        XCTAssertEqual(result.words[2].expected, "teatro")
    }

    func testEmptyAnswerMissesEverything() {
        let result = DictationCheck.check(typed: "   ", expected: "Buongiorno a tutti")
        XCTAssertEqual(result.words.map(\.mark), [.missing, .missing, .missing])
        XCTAssertEqual(result.score, 0)
    }

    func testEmptyExpectedSentenceGivesNothingToCheck() {
        let result = DictationCheck.check(typed: "ciao", expected: " ")
        XCTAssertTrue(result.words.isEmpty)
        XCTAssertEqual(result.score, 0)
        XCTAssertFalse(result.isPerfect)
    }

    func testApostrophesStayInsideWords() {
        XCTAssertEqual(marks("Bevo l’acqua", "Bevo l'acqua."), [.correct, .correct])
        XCTAssertEqual(marks("I don't know", "I don't know"), [.correct, .correct, .correct])
    }

    func testScoreNeverGoesBelowZero() {
        let result = DictationCheck.check(typed: "a b c d e f g h", expected: "casa")
        XCTAssertEqual(result.score, 0)
    }
}
