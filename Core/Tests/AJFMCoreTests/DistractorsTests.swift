import XCTest
@testable import AJFMCore

final class DistractorsTests: XCTestCase {

    // MARK: - Язык

    func testDetectsCyrillic() {
        XCTAssertEqual(Distractors.script(of: "раскрыть прикрытие, выдать"), .cyrillic)
    }

    func testDetectsEnglishDefinition() {
        XCTAssertEqual(Distractors.script(of: "to try to sell an idea or product by explaining why it's good"),
                       .english)
    }

    func testDetectsPortugueseByDiacritics() {
        XCTAssertEqual(Distractors.script(of: "revelação"), .otherLatin)
    }

    func testDetectsPortugueseByFunctionWords() {
        XCTAssertEqual(Distractors.script(of: "fazer de conta que"), .otherLatin)
    }

    func testSingleEnglishWordIsEnglish() {
        XCTAssertEqual(Distractors.script(of: "startup"), .english)
    }

    func testDigitsAndPunctuationAreUnknown() {
        XCTAssertEqual(Distractors.script(of: "123 — !"), .unknown)
    }

    // MARK: - Выбор

    private let pool = [
        "раскрыть прикрытие, выдать", "подача идеи", "стартап, молодая компания", "с нуля",
        "a new small company, usually in tech", "from the very beginning",
        "to try to sell an idea or product by explaining why it's good",
    ]

    func testRussianAnswerGetsOnlyRussianDistractors() {
        var generator = SplitMix64(seed: 1)
        let picked = Distractors.pick(correct: "подача идеи", pool: pool, using: &generator)
        XCTAssertEqual(picked.count, 3)
        XCTAssertTrue(picked.allSatisfy { Distractors.script(of: $0) == .cyrillic }, "\(picked)")
    }

    func testEnglishAnswerGetsOnlyEnglishDistractors() {
        var generator = SplitMix64(seed: 2)
        let picked = Distractors.pick(correct: "to try to sell an idea or product by explaining why it's good",
                                      pool: pool, using: &generator)
        XCTAssertEqual(picked.count, 2, "английских вариантов в пуле всего два, чужой язык не берём")
        XCTAssertTrue(picked.allSatisfy { Distractors.script(of: $0) == .english })
    }

    func testCorrectAnswerIsNeverADistractor() {
        var generator = SplitMix64(seed: 3)
        for _ in 0..<50 {
            let picked = Distractors.pick(correct: "с нуля", pool: pool + ["С нуля  "], using: &generator)
            XCTAssertFalse(picked.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .contains("с нуля"))
        }
    }

    func testDuplicatesInPoolAreNotRepeated() {
        var generator = SplitMix64(seed: 4)
        let picked = Distractors.pick(correct: "кот", pool: ["собака", "собака", "Собака", "мышь"],
                                      using: &generator)
        XCTAssertEqual(Set(picked.map { $0.lowercased() }).count, picked.count)
        XCTAssertEqual(picked.count, 2)
    }

    func testEmptyPoolGivesNoDistractors() {
        var generator = SplitMix64(seed: 5)
        XCTAssertEqual(Distractors.pick(correct: "кот", pool: [], using: &generator), [])
    }

    func testEmptyStringsInPoolAreIgnored() {
        var generator = SplitMix64(seed: 6)
        XCTAssertEqual(Distractors.pick(correct: "кот", pool: ["", "  "], using: &generator), [])
    }

    func testPrefersSimilarLengthWhenThereIsChoice() {
        var generator = SplitMix64(seed: 7)
        let longOnes = (1...5).map { "очень длинное толкование слова номер \($0) с подробностями" }
        let shortOnes = ["дом", "лес", "сад"]
        let picked = Distractors.pick(correct: "кот", pool: longOnes + shortOnes, using: &generator)
        XCTAssertEqual(Set(picked), Set(shortOnes))
    }

    func testFillsUpWithOtherLengthsWhenNeeded() {
        var generator = SplitMix64(seed: 8)
        let picked = Distractors.pick(correct: "кот",
                                      pool: ["дом", "очень длинное толкование слова с подробностями"],
                                      using: &generator)
        XCTAssertEqual(picked.count, 2)
    }

    func testSameSeedGivesSameChoice() {
        var first = SplitMix64(seed: 9)
        var second = SplitMix64(seed: 9)
        XCTAssertEqual(Distractors.pick(correct: "подача идеи", pool: pool, using: &first),
                       Distractors.pick(correct: "подача идеи", pool: pool, using: &second))
    }
}
