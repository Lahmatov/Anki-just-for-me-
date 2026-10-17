import XCTest
@testable import AJFMCore

final class RegionPolicyTests: XCTestCase {
    func testRussianStoreWorksWithoutServer() {
        XCTAssertFalse(RegionPolicy.allowsServer(storefront: "RUS"))
    }

    func testCodeIsCaseAndSpaceInsensitive() {
        XCTAssertFalse(RegionPolicy.allowsServer(storefront: " rus "))
    }

    func testOtherStoresUseServer() {
        for code in ["PRT", "USA", "DEU", "ISR", "GEO", "KAZ"] {
            XCTAssertTrue(RegionPolicy.allowsServer(storefront: code), code)
        }
    }

    func testUnknownStoreDoesNotSwitchServerOff() {
        XCTAssertTrue(RegionPolicy.allowsServer(storefront: nil))
        XCTAssertTrue(RegionPolicy.allowsServer(storefront: ""))
    }

    func testTwoLetterCodeIsNotMistakenForRussia() {
        // StoreKit отдаёт три буквы; «RU» — не тот формат и не повод отключать.
        XCTAssertTrue(RegionPolicy.allowsServer(storefront: "RU"))
    }
}
