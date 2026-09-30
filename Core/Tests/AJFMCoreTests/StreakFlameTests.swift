import XCTest
@testable import AJFMCore

final class StreakFlameTests: XCTestCase {

    func testNoStreakNoFlame() {
        XCTAssertEqual(StreakFlame.intensity(days: 0), 0)
        XCTAssertEqual(StreakFlame.intensity(days: -4), 0)
    }

    func testIntensityGrowsWithDays() {
        var previous = 0.0
        for days in 1...StreakFlame.fullAtDays {
            let value = StreakFlame.intensity(days: days)
            XCTAssertGreaterThan(value, previous, "день \(days)")
            previous = value
        }
    }

    func testIntensityCapsAtTheLimit() {
        XCTAssertEqual(StreakFlame.intensity(days: StreakFlame.fullAtDays), 1, accuracy: 0.0001)
        XCTAssertEqual(StreakFlame.intensity(days: 500), 1, accuracy: 0.0001)
    }

    func testFirstWeekIsVisiblyDifferent() {
        // Логарифм: первая неделя даёт заметный рост, а не доли процента.
        XCTAssertGreaterThan(StreakFlame.intensity(days: 7) - StreakFlame.intensity(days: 1), 0.3)
    }

    func testSizeStaysReasonable() {
        XCTAssertEqual(StreakFlame.size(days: 0), 30)
        XCTAssertEqual(StreakFlame.size(days: 1000), 54, accuracy: 0.001)
    }

    func testStagesByDays() {
        XCTAssertEqual(StreakFlame.stage(days: 1), .spark)
        XCTAssertEqual(StreakFlame.stage(days: 7), .flame)
        XCTAssertEqual(StreakFlame.stage(days: 30), .blaze)
        XCTAssertEqual(StreakFlame.stage(days: 60), .blue)
    }
}
