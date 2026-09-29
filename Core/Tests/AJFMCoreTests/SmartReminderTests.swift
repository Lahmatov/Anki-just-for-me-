import XCTest
@testable import AJFMCore

final class SmartReminderTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Обычное время

    func testTooLittleHistoryHasNoUsualTime() {
        let sessions = [date(1, 20), date(2, 20)]
        XCTAssertNil(SmartReminder.usualStart(sessions: sessions, now: date(10, 12), cutoffHour: 4,
                                              calendar: calendar))
    }

    func testUsualTimeIsTheMedianStart() {
        let sessions = [date(1, 20), date(2, 20, 30), date(3, 19, 40), date(4, 21), date(5, 20, 10)]
        let usual = SmartReminder.usualStart(sessions: sessions, now: date(6, 12), cutoffHour: 4,
                                             calendar: calendar)
        XCTAssertEqual(usual, SmartReminder.Time(hour: 20, minute: 10))
    }

    func testOneOddNightDoesNotMoveTheTime() {
        let sessions = [date(1, 20), date(2, 20), date(3, 20), date(4, 20), date(5, 3)]
        XCTAssertEqual(SmartReminder.usualStart(sessions: sessions, now: date(6, 12), cutoffHour: 4,
                                                calendar: calendar),
                       SmartReminder.Time(hour: 20, minute: 0))
    }

    func testOnlyTheFirstSessionOfEachDayCounts() {
        // Утром — начало учёбы; вечерние добивки того же дня привычку не меняют.
        let sessions = [date(1, 8), date(1, 22), date(2, 8), date(2, 23), date(3, 8), date(3, 21)]
        XCTAssertEqual(SmartReminder.usualStart(sessions: sessions, now: date(4, 12), cutoffHour: 4,
                                                calendar: calendar),
                       SmartReminder.Time(hour: 8, minute: 0))
    }

    func testNightOwlAroundMidnightIsOneHabit() {
        // 23:50, 00:20 и 00:10 — одна привычка, а не «полдень» в среднем.
        let sessions = [date(1, 23, 50), date(3, 0, 20), date(4, 0, 10)]
        XCTAssertEqual(SmartReminder.usualStart(sessions: sessions, now: date(6, 12), cutoffHour: 4,
                                                calendar: calendar),
                       SmartReminder.Time(hour: 0, minute: 10))
    }

    func testOldHistoryIsIgnored() {
        let old = [date(1, 8), date(2, 8), date(3, 8)]
        let recent = [date(27, 20), date(28, 20), date(29, 20)]
        XCTAssertEqual(SmartReminder.usualStart(sessions: old + recent, now: date(30, 12), cutoffHour: 4,
                                                calendar: calendar),
                       SmartReminder.Time(hour: 20, minute: 0))
    }

    func testFutureSessionsAreIgnored() {
        let sessions = [date(1, 20), date(2, 20), date(20, 8)]
        XCTAssertNil(SmartReminder.usualStart(sessions: sessions, now: date(3, 12), cutoffHour: 4,
                                              calendar: calendar))
    }

    // MARK: - Время напоминания

    func testReminderComesAfterTheUsualTimeRoundedToFive() {
        XCTAssertEqual(SmartReminder.reminderTime(forUsual: .init(hour: 20, minute: 10)), .init(hour: 20, minute: 25))
        XCTAssertEqual(SmartReminder.reminderTime(forUsual: .init(hour: 20, minute: 11)), .init(hour: 20, minute: 30))
    }

    func testReminderWrapsPastMidnight() {
        XCTAssertEqual(SmartReminder.reminderTime(forUsual: .init(hour: 23, minute: 50)), .init(hour: 0, minute: 5))
    }

    func testTimeFromMinutesWrapsBothWays() {
        XCTAssertEqual(SmartReminder.Time(minutes: -10), .init(hour: 23, minute: 50))
        XCTAssertEqual(SmartReminder.Time(minutes: 1450), .init(hour: 0, minute: 10))
    }

    // MARK: - План

    private let evening = SmartReminder.Time(hour: 20, minute: 25)

    func testTodayIsIncludedWhenNotStudiedYet() {
        let plan = SmartReminder.schedule(at: evening, now: date(10, 12), studiedToday: false,
                                          cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(plan.first, date(10, 20, 25))
        XCTAssertEqual(plan.count, SmartReminder.daysAhead)
    }

    func testStudiedTodaySkipsToTomorrow() {
        let plan = SmartReminder.schedule(at: evening, now: date(10, 12), studiedToday: true,
                                          cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(plan.first, date(11, 20, 25))
        XCTAssertFalse(plan.contains { calendar.isDate($0, inSameDayAs: date(10, 0)) })
    }

    func testPassedTimeTodaySkipsToTomorrow() {
        let plan = SmartReminder.schedule(at: evening, now: date(10, 21), studiedToday: false,
                                          cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(plan.first, date(11, 20, 25))
    }

    func testOneReminderPerDay() {
        let plan = SmartReminder.schedule(at: evening, now: date(10, 12), studiedToday: false,
                                          cutoffHour: 4, calendar: calendar)
        let days = Set(plan.map { calendar.startOfDay(for: $0) })
        XCTAssertEqual(days.count, plan.count)
        XCTAssertEqual(plan, plan.sorted())
    }

    func testAfterMidnightTimeBelongsToTheSameStudyDay() {
        // 00:10 при переходе дня в 4 утра — ещё «сегодня» для совы.
        let owl = SmartReminder.Time(hour: 0, minute: 10)
        let plan = SmartReminder.schedule(at: owl, now: date(10, 23), studiedToday: false,
                                          cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(plan.first, date(11, 0, 10))
        let studied = SmartReminder.schedule(at: owl, now: date(10, 23), studiedToday: true,
                                             cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(studied.first, date(12, 0, 10))
    }

    func testZeroDaysPlansNothing() {
        XCTAssertEqual(SmartReminder.schedule(at: evening, now: date(10, 12), studiedToday: false,
                                              cutoffHour: 4, calendar: calendar, days: 0), [])
    }
}
