import XCTest
@testable import AJFMCore

final class DailyGoalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Loc.language = .russian
    }

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    // MARK: - Время

    func testDurationsAreSummed() {
        XCTAssertEqual(DailyGoal.studiedSeconds([10, 20, 30]), 60)
    }

    func testEachReviewIsCappedAtAMinute() {
        // Карточку оставили открытой на полчаса — засчитана минута.
        XCTAssertEqual(DailyGoal.studiedSeconds([1_800, 10]), 70)
    }

    func testBrokenDurationsCountAsZero() {
        XCTAssertEqual(DailyGoal.studiedSeconds([-5, .nan, .infinity, 12]), 12)
    }

    func testNoReviewsIsZero() {
        XCTAssertEqual(DailyGoal.studiedSeconds([]), 0)
    }

    // MARK: - Доля

    func testProgressIsAFractionOfTheGoal() {
        XCTAssertEqual(DailyGoal.progress(studiedSeconds: 450, goalMinutes: 15), 0.5)
    }

    func testProgressStopsAtOne() {
        XCTAssertEqual(DailyGoal.progress(studiedSeconds: 10_000, goalMinutes: 15), 1)
    }

    func testZeroGoalIsNotAFreeWin() {
        // Деление на ноль и «выполнено» без цели — оба неверны.
        XCTAssertEqual(DailyGoal.progress(studiedSeconds: 600, goalMinutes: 0), 0)
        XCTAssertEqual(DailyGoal.progress(studiedSeconds: 600, goalMinutes: -10), 0)
    }

    func testBrokenStudiedTimeGivesZeroProgress() {
        XCTAssertEqual(DailyGoal.progress(studiedSeconds: .nan, goalMinutes: 15), 0)
    }

    func testWholeMinutesRoundDown() {
        XCTAssertEqual(DailyGoal.wholeMinutes(59), 0)
        XCTAssertEqual(DailyGoal.wholeMinutes(60), 1)
        XCTAssertEqual(DailyGoal.wholeMinutes(179), 2)
        XCTAssertEqual(DailyGoal.wholeMinutes(-3), 0)
    }

    // MARK: - Текст

    func testMinutesAndHoursAreFormatted() {
        XCTAssertEqual(DailyGoal.format(minutes: 15), "15 минут")
        XCTAssertEqual(DailyGoal.format(minutes: 60), "1 час")
        XCTAssertEqual(DailyGoal.format(minutes: 120), "2 часа")
        XCTAssertEqual(DailyGoal.format(minutes: 90), "1 ч 30 мин")
    }

    func testFormatInOtherLanguages() {
        Loc.language = .english
        XCTAssertEqual(DailyGoal.format(minutes: 60), "1 hour")
        XCTAssertEqual(DailyGoal.format(minutes: 5), "5 minutes")
        Loc.language = .portuguese
        XCTAssertEqual(DailyGoal.format(minutes: 120), "2 horas")
    }

    // MARK: - Сохранённое значение

    func testGarbageFallsBackToTheDefault() {
        XCTAssertEqual(DailyGoal.sanitized(0), DailyGoal.defaultMinutes)
        XCTAssertEqual(DailyGoal.sanitized(-1), DailyGoal.defaultMinutes)
        XCTAssertEqual(DailyGoal.sanitized(100_000), DailyGoal.defaultMinutes)
        XCTAssertEqual(DailyGoal.sanitized(45), 45)
    }

    func testOptionsAreSortedAndIncludeTheDefault() {
        XCTAssertEqual(DailyGoal.options, DailyGoal.options.sorted())
        XCTAssertTrue(DailyGoal.options.contains(DailyGoal.defaultMinutes))
    }
}
