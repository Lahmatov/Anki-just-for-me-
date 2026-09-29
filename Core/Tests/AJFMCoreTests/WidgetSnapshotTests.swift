import XCTest
@testable import AJFMCore

final class WidgetSnapshotTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func snapshot(day: Int, due: Int = 12, streak: Int = 8, studied: Bool = false) -> WidgetSnapshot {
        WidgetSnapshot(dueCards: due, streakDays: streak, studiedToday: studied, goalFraction: 0.5,
                       studyDay: date(day, 4), cutoffHour: 4, language: "ru")
    }

    func testNoSnapshotIsEmpty() {
        XCTAssertEqual(WidgetSnapshot.presentation(of: nil, now: date(10, 12), calendar: calendar), .empty)
    }

    func testSameStudyDayShowsTheNumbers() {
        XCTAssertEqual(WidgetSnapshot.presentation(of: snapshot(day: 10), now: date(10, 23), calendar: calendar),
                       .today(due: 12, streak: 8, studied: false, goal: 0.5))
    }

    func testAfterMidnightButBeforeCutoffIsStillToday() {
        // В 2 ночи учебный день ещё вчерашний — цифры в силе.
        XCTAssertEqual(WidgetSnapshot.presentation(of: snapshot(day: 10), now: date(11, 2), calendar: calendar),
                       .today(due: 12, streak: 8, studied: false, goal: 0.5))
    }

    func testNextDayHidesTheStaleCountButKeepsTheStreak() {
        XCTAssertEqual(WidgetSnapshot.presentation(of: snapshot(day: 10, studied: true), now: date(11, 9),
                                                   calendar: calendar),
                       .newDay(streak: 8, streakAtRisk: true))
    }

    func testLongAbsenceDoesNotPromiseAStreak() {
        XCTAssertEqual(WidgetSnapshot.presentation(of: snapshot(day: 5), now: date(11, 9), calendar: calendar),
                       .newDay(streak: 0, streakAtRisk: false))
    }

    func testNoStreakIsNotAtRisk() {
        XCTAssertEqual(WidgetSnapshot.presentation(of: snapshot(day: 10, streak: 0), now: date(11, 9),
                                                   calendar: calendar),
                       .newDay(streak: 0, streakAtRisk: false))
    }

    func testNextRefreshIsTheNextStudyDay() {
        XCTAssertEqual(WidgetSnapshot.nextRefresh(after: date(10, 12), cutoffHour: 4, calendar: calendar),
                       date(11, 4))
        XCTAssertEqual(WidgetSnapshot.nextRefresh(after: date(11, 2), cutoffHour: 4, calendar: calendar),
                       date(11, 4))
    }

    func testRoundTripsThroughData() throws {
        let original = snapshot(day: 10)
        XCTAssertEqual(WidgetSnapshot.decode(try original.encoded()), original)
    }

    func testBrokenDataIsNoSnapshot() {
        XCTAssertNil(WidgetSnapshot.decode(Data("nope".utf8)))
        XCTAssertNil(WidgetSnapshot.decode(nil))
        XCTAssertNil(WidgetSnapshot.decode(Data(#"{"dueCards":1}"#.utf8)))
    }

    func testValuesAreClamped() {
        let odd = WidgetSnapshot(dueCards: -3, streakDays: -1, studiedToday: false, goalFraction: .nan,
                                 studyDay: date(10, 4), cutoffHour: 4, language: "en")
        XCTAssertEqual(odd.dueCards, 0)
        XCTAssertEqual(odd.streakDays, 0)
        XCTAssertEqual(odd.goalFraction, 0)
        let over = WidgetSnapshot(dueCards: 1, streakDays: 1, studiedToday: true, goalFraction: 3,
                                  studyDay: date(10, 4), cutoffHour: 4, language: "en")
        XCTAssertEqual(over.goalFraction, 1)
    }
}
