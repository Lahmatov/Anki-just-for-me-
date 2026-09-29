import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Снимок для виджета из настоящей базы. Правила показа — в WidgetSnapshotTests ядра.
@MainActor
final class WidgetBridgeTests: XCTestCase {

    func testEmptyDatabaseGivesAnHonestZeroSnapshot() throws {
        let snapshot = WidgetBridge.makeSnapshot(context: try TestDB.makeContext())
        XCTAssertEqual(snapshot.dueCards, 0)
        XCTAssertEqual(snapshot.streakDays, 0)
        XCTAssertFalse(snapshot.studiedToday)
        XCTAssertEqual(snapshot.goalFraction, 0)
        XCTAssertEqual(snapshot.language, Loc.language.rawValue)
    }

    func testNewWordsCountAsWaitingCards() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            notes: (1...3).map { NoteData(term: "word\($0)", translation: "слово \($0)") })))
        XCTAssertGreaterThan(WidgetBridge.makeSnapshot(context: context).dueCards, 0)
    }

    func testSnapshotBelongsToTodaysStudyDay() throws {
        let now = Date()
        let snapshot = WidgetBridge.makeSnapshot(context: try TestDB.makeContext(), now: now)
        if case .today = WidgetSnapshot.presentation(of: snapshot, now: now) { return }
        XCTFail("свежий снимок обязан показываться с цифрами")
    }

    func testWithoutAppGroupNothingIsWritten() {
        // В тестовой сборке группа не подставлена: мост молча ничего не делает.
        XCTAssertNil(WidgetBridge.groupID)
    }
}
