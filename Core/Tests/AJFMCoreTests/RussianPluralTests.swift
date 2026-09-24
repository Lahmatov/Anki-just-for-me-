import XCTest
@testable import AJFMCore

final class RussianPluralTests: XCTestCase {

    private func day(_ n: Int) -> String {
        RussianPlural.form(n, one: "день", few: "дня", many: "дней")
    }

    func testOne() {
        XCTAssertEqual(day(1), "день")
        XCTAssertEqual(day(21), "день")
        XCTAssertEqual(day(101), "день")
    }

    func testFew() {
        XCTAssertEqual(day(2), "дня")
        XCTAssertEqual(day(3), "дня")
        XCTAssertEqual(day(4), "дня")
        XCTAssertEqual(day(22), "дня")
        XCTAssertEqual(day(104), "дня")
    }

    func testMany() {
        XCTAssertEqual(day(0), "дней")
        XCTAssertEqual(day(5), "дней")
        XCTAssertEqual(day(20), "дней")
        XCTAssertEqual(day(100), "дней")
    }

    func testTeensAreAlwaysMany() {
        // 11–14 — исключение, на котором спотыкается наивная проверка
        // последней цифры: «11 день», «12 дня».
        for n in [11, 12, 13, 14, 111, 112, 213, 1014] {
            XCTAssertEqual(day(n), "дней", "\(n)")
        }
    }

    func testNegativeNumbersFollowTheSameRules() {
        XCTAssertEqual(day(-1), "день")
        XCTAssertEqual(day(-3), "дня")
        XCTAssertEqual(day(-12), "дней")
    }

    func testPhrases() {
        XCTAssertEqual(RussianPlural.days(3), "3 дня")
        XCTAssertEqual(RussianPlural.words(21), "21 слово")
        XCTAssertEqual(RussianPlural.words(150), "150 слов")
        XCTAssertEqual(RussianPlural.cards(2), "2 карточки")
        XCTAssertEqual(RussianPlural.cards(11), "11 карточек")
    }

    func testExtremeValuesDoNotCrash() {
        // abs(Int.min) переполняется; число берём по модулю без знака.
        XCTAssertEqual(day(Int.min), "дней")  // …808
        XCTAssertEqual(day(Int.max), "дней")  // …807
    }

    func testAccusativeChangesOnlyTheSingular() {
        XCTAssertEqual(RussianPlural.cardsAccusative(1), "1 карточку")
        XCTAssertEqual(RussianPlural.cardsAccusative(21), "21 карточку")
        XCTAssertEqual(RussianPlural.cardsAccusative(3), "3 карточки")
        XCTAssertEqual(RussianPlural.cardsAccusative(11), "11 карточек")
        XCTAssertEqual(RussianPlural.cardsAccusative(25), "25 карточек")
    }
}
