import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Какое время выберет напоминание — по истории из настоящей базы.
/// Сами правила (медиана, окно, запас) — в SmartReminderTests ядра.
@MainActor
final class ReminderPlanningTests: XCTestCase {

    private let keys = [SettingsKey.reminderSmart, SettingsKey.reminderHour, SettingsKey.reminderMinute]

    override func setUp() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func context(withStudyAt hour: Int, days: Int, now: Date,
                         honest: Bool = true) throws -> ModelContext {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            notes: [NoteData(term: "word", translation: "слово")])))
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        let calendar = Calendar.current
        for offset in 1...max(days, 1) where days > 0 {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            let entry = Review(card: card, grade: 3, timeSpent: 1, algorithm: "fsrs6", isHonest: honest)
            entry.timestamp = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            context.insert(entry)
        }
        try context.save()
        return context
    }

    private var now: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    func testWithoutHistoryTheChosenTimeIsUsed() throws {
        UserDefaults.standard.set(9, forKey: SettingsKey.reminderHour)
        UserDefaults.standard.set(30, forKey: SettingsKey.reminderMinute)
        let planned = NotificationService.plannedTime(context: try context(withStudyAt: 19, days: 0, now: now),
                                                      now: now)
        XCTAssertFalse(planned.learned)
        XCTAssertEqual(planned.time, SmartReminder.Time(hour: 9, minute: 30))
    }

    func testHabitFromHistoryWinsOverTheClock() throws {
        let planned = NotificationService.plannedTime(context: try context(withStudyAt: 19, days: 4, now: now),
                                                      now: now)
        XCTAssertTrue(planned.learned)
        XCTAssertEqual(planned.time, SmartReminder.Time(hour: 19, minute: 15))
    }

    func testSmartOffUsesTheClockEvenWithHistory() throws {
        UserDefaults.standard.set(false, forKey: SettingsKey.reminderSmart)
        let planned = NotificationService.plannedTime(context: try context(withStudyAt: 19, days: 4, now: now),
                                                      now: now)
        XCTAssertFalse(planned.learned)
        XCTAssertEqual(planned.time, SmartReminder.Time(hour: 20, minute: 0), "время по умолчанию")
    }

    func testManualEditsAreNotAHabit() throws {
        // Правки карточек руками — не учёба: по ним привычку не выводим.
        let planned = NotificationService.plannedTime(
            context: try context(withStudyAt: 7, days: 4, now: now, honest: false), now: now)
        XCTAssertFalse(planned.learned)
    }
}
