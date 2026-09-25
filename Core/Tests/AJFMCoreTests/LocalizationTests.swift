import XCTest
@testable import AJFMCore

final class LocalizationTests: XCTestCase {

    override func tearDown() {
        // Язык — общее состояние: остальные тесты ждут русский.
        Loc.language = .russian
    }

    func testTrPicksTheCurrentLanguage() {
        Loc.language = .russian
        XCTAssertEqual(tr("да", "sim", "yes"), "да")
        Loc.language = .portuguese
        XCTAssertEqual(tr("да", "sim", "yes"), "sim")
        Loc.language = .english
        XCTAssertEqual(tr("да", "sim", "yes"), "yes")
    }

    func testRussianCountsKeepThreeForms() {
        Loc.language = .russian
        XCTAssertEqual(Counted.days(1), "1 день")
        XCTAssertEqual(Counted.days(3), "3 дня")
        XCTAssertEqual(Counted.days(11), "11 дней")
        XCTAssertEqual(Counted.cardsAccusative(21), "21 карточку")
        XCTAssertEqual(Counted.times(2), "2 раза")
    }

    func testPortugueseSingularOnlyForOne() {
        Loc.language = .portuguese
        XCTAssertEqual(Counted.words(1), "1 palavra")
        XCTAssertEqual(Counted.words(0), "0 palavras", "no português europeu 0 é plural")
        XCTAssertEqual(Counted.words(21), "21 palavras")
        XCTAssertEqual(Counted.cards(2), "2 cartões")
    }

    func testEnglishSingularOnlyForOne() {
        Loc.language = .english
        XCTAssertEqual(Counted.days(1), "1 day")
        XCTAssertEqual(Counted.days(0), "0 days")
        XCTAssertEqual(Counted.days(21), "21 days")
        XCTAssertEqual(Counted.cardsAccusative(1), "1 card")
    }

    func testNegativeAndExtremeCountsDoNotCrash() {
        for language in AppLanguage.allCases {
            Loc.language = language
            XCTAssertFalse(Counted.words(Int.min).isEmpty)
            XCTAssertFalse(Counted.words(-1).isEmpty)
        }
    }
}
