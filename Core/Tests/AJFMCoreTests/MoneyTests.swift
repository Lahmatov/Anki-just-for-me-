import XCTest
@testable import AJFMCore

final class MoneyTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let portuguese = Locale(identifier: "pt_PT")

    func testEnglishUsesDollarSignAndDot() {
        XCTAssertEqual(Money.usd(0.0123, fractionDigits: 3, locale: english), "$0.012")
    }

    func testFractionDigitsAreRespected() {
        XCTAssertEqual(Money.usd(5, fractionDigits: 0, locale: english), "$5")
        XCTAssertEqual(Money.usd(1.5, locale: english), "$1.50")
    }

    func testPortugueseUsesDecimalComma() {
        let text = Money.usd(0.25, locale: portuguese)
        XCTAssertTrue(text.contains("0,25"), text)
        XCTAssertTrue(text.contains("US$") || text.contains("$"), text)
    }

    func testZeroIsStillAMoneyAmount() {
        XCTAssertEqual(Money.usd(0, locale: english), "$0.00")
    }
}
