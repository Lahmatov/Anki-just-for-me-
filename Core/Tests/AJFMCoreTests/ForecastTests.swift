import XCTest
@testable import AJFMCore

final class ForecastTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func upcoming(_ dates: [Date], days: Int = 7, now: Date) -> [ForecastDay] {
        Forecast.upcoming(
            dueDates: dates, days: days, from: now, cutoffHour: 4, calendar: calendar)
    }

    func testGivesOneBucketPerDay() {
        let forecast = upcoming([], days: 30, now: date(10))
        XCTAssertEqual(forecast.count, 30)
        XCTAssertTrue(forecast.allSatisfy { $0.dueCount == 0 })
    }

    func testCardsLandOnTheirDay() {
        let forecast = upcoming([date(11), date(11, 20), date(13)], now: date(10))
        XCTAssertEqual(forecast[1].dueCount, 2)
        XCTAssertEqual(forecast[3].dueCount, 1)
        XCTAssertEqual(forecast[0].dueCount, 0)
    }

    func testOverdueCardsCountAsToday() {
        // Просроченное ждёт именно сегодня — прятать его из прогноза нечестно.
        let forecast = upcoming([date(1), date(5)], now: date(10))
        XCTAssertEqual(forecast[0].dueCount, 2)
    }

    func testCardsBeyondTheHorizonAreIgnored() {
        let forecast = upcoming([date(20)], days: 7, now: date(10))
        XCTAssertEqual(Forecast.total(forecast), 0)
    }

    func testLateNightDueTimeBelongsToPreviousDay() {
        // Карточка на 2 ночи 12-го — это вечер 11-го, учебный день ещё не кончился.
        let forecast = upcoming([date(12, 2)], now: date(10))
        XCTAssertEqual(forecast[1].dueCount, 1)
    }

    func testPeakFindsTheWorstDay() {
        let forecast = upcoming([date(12), date(12), date(12), date(13)], now: date(10))
        let peak = Forecast.peak(forecast)
        XCTAssertEqual(peak?.dueCount, 3)
        XCTAssertEqual(peak?.date, date(12, 4))
    }

    func testTotalsAndAverage() {
        let forecast = upcoming([date(11), date(11), date(12)], days: 10, now: date(10))
        XCTAssertEqual(Forecast.total(forecast), 3)
        XCTAssertEqual(Forecast.averagePerDay(forecast), 0.3, accuracy: 0.001)
    }

    func testEmptyForecastHasNoPeak() {
        XCTAssertNil(Forecast.peak([]))
        XCTAssertEqual(Forecast.averagePerDay([]), 0)
    }

    // MARK: - Активность

    func testWeeklyActivityBuckets() {
        // 9 марта 2026 — понедельник.
        let activity = Forecast.weeklyActivity(
            reviewDates: [date(9), date(10), date(11), date(3)],
            weeks: 4, from: date(13), calendar: calendar)

        XCTAssertEqual(activity.count, 4)
        XCTAssertEqual(activity.last?.dueCount, 3, "текущая неделя")
        XCTAssertEqual(activity[activity.count - 2].dueCount, 1, "прошлая неделя")
    }

    func testActivityIgnoresOlderWeeks() {
        let old = calendar.date(from: DateComponents(year: 2025, month: 12, day: 1))!
        let activity = Forecast.weeklyActivity(
            reviewDates: [old], weeks: 4, from: date(13), calendar: calendar)
        XCTAssertEqual(activity.reduce(0) { $0 + $1.dueCount }, 0)
    }

    func testActivityIsOrderedOldestFirst() {
        let activity = Forecast.weeklyActivity(
            reviewDates: [], weeks: 5, from: date(13), calendar: calendar)
        XCTAssertEqual(activity, activity.sorted { $0.date < $1.date })
    }

    func testZeroWeeksGivesNothing() {
        XCTAssertTrue(Forecast.weeklyActivity(
            reviewDates: [date(9)], weeks: 0, from: date(13), calendar: calendar).isEmpty)
    }
}
