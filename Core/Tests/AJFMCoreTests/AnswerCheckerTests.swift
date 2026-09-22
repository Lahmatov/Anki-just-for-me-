import XCTest
@testable import AJFMCore

final class AnswerCheckerTests: XCTestCase {

    private func verdict(_ input: String, _ expected: String,
                         synonyms: [String] = [], strict: Bool = false) -> AnswerCheck.Verdict {
        AnswerChecker.check(
            input: input, expected: expected, synonyms: synonyms, strict: strict).verdict
    }

    func testExactMatch() {
        XCTAssertEqual(verdict("leverage", "leverage"), .correct)
    }

    func testIgnoresCaseAndSurroundingSpaces() {
        XCTAssertEqual(verdict("  LEVERAGE  ", "leverage"), .correct)
        XCTAssertEqual(verdict("Pull   Off", "pull off"), .correct)
    }

    func testIgnoresTrailingPunctuation() {
        XCTAssertEqual(verdict("leverage.", "leverage"), .correct)
        XCTAssertEqual(verdict("really!", "really"), .correct)
    }

    func testIgnoresArticlesAndInfinitiveParticle() {
        XCTAssertEqual(verdict("the leverage", "leverage"), .correct)
        XCTAssertEqual(verdict("pull off", "to pull off"), .correct)
        XCTAssertEqual(verdict("to pull off", "pull off"), .correct)
    }

    func testAcceptsCurlyApostrophe() {
        // Клавиатура iOS ставит типографский апостроф — это не ошибка пользователя.
        XCTAssertEqual(verdict("don\u{2019}t", "don't"), .correct)
    }

    func testSynonymsAreAccepted() {
        let result = AnswerChecker.check(
            input: "manage", expected: "to pull off", synonyms: ["manage", "succeed in"])
        XCTAssertEqual(result.verdict, .correct)
        XCTAssertEqual(result.matched, "manage")
    }

    func testSingleTypoIsForgivenButReported() {
        let result = AnswerChecker.check(input: "leverge", expected: "leverage")
        XCTAssertEqual(result.verdict, .typo)
        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.matched, "leverage")
        XCTAssertNotNil(result.hint)
    }

    func testTwoTyposAreWrong() {
        XCTAssertEqual(verdict("levrge", "leverage"), .wrong)
    }

    func testShortWordsGetNoTypoForgiveness() {
        // На коротких словах «опечатка» — это уже другое слово.
        XCTAssertEqual(verdict("cat", "cut"), .wrong)
        XCTAssertEqual(verdict("bad", "bed"), .wrong)
        XCTAssertEqual(verdict("ship", "shop"), .typo, "от четырёх букв поблажка работает")
    }

    func testStrictModeRejectsTypos() {
        // Карточка на правописание существует ровно ради точности написания.
        XCTAssertEqual(verdict("leverge", "leverage", strict: true), .wrong)
        XCTAssertEqual(verdict("leverage", "leverage", strict: true), .correct)
        XCTAssertEqual(verdict("The Leverage", "leverage", strict: true), .correct,
                       "регистр и артикль — не ошибка написания")
    }

    func testEmptyInputIsWrong() {
        let result = AnswerChecker.check(input: "   ", expected: "leverage")
        XCTAssertEqual(result.verdict, .wrong)
        XCTAssertEqual(result.hint, "Пустой ответ")
    }

    func testWrongAnswerShowsTheRightOne() {
        let result = AnswerChecker.check(input: "потолок", expected: "leverage")
        XCTAssertEqual(result.verdict, .wrong)
        XCTAssertEqual(result.hint, "Правильно: «leverage»")
    }

    func testCompletelyDifferentWordsAreWrong() {
        XCTAssertEqual(verdict("without", "with"), .wrong)
        XCTAssertEqual(verdict("running", "run"), .wrong)
    }

    // MARK: - Расстояние Левенштейна

    func testEditDistanceBasics() {
        XCTAssertEqual(AnswerChecker.editDistance("kitten", "kitten", limit: 3), 0)
        XCTAssertEqual(AnswerChecker.editDistance("kitten", "sitten", limit: 3), 1)
        XCTAssertEqual(AnswerChecker.editDistance("kitten", "sittin", limit: 3), 2)
        XCTAssertEqual(AnswerChecker.editDistance("kitten", "sitting", limit: 3), 3)
    }

    func testEditDistanceHandlesEmptyStrings() {
        XCTAssertEqual(AnswerChecker.editDistance("", "", limit: 2), 0)
        XCTAssertEqual(AnswerChecker.editDistance("abc", "", limit: 5), 3)
        XCTAssertEqual(AnswerChecker.editDistance("", "abc", limit: 5), 3)
    }

    func testEditDistanceBailsOutEarly() {
        // За пределами лимита точное значение не нужно — важно лишь «дальше чем».
        XCTAssertGreaterThan(AnswerChecker.editDistance("abcdef", "uvwxyz", limit: 1), 1)
        XCTAssertGreaterThan(AnswerChecker.editDistance("a", "abcdefgh", limit: 2), 2)
    }
}
