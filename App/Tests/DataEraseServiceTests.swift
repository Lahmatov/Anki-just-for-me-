import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// «Удалить все данные» должно удалять именно всё: остаток в базе после
/// такой кнопки — нарушение обещания, а не мелкая недоработка.
@MainActor
final class DataEraseServiceTests: XCTestCase {

    private func count<Model: PersistentModel>(_ type: Model.Type, in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Model>())) ?? -1
    }

    func testEveryTableIsEmptyAfterErase() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            folder: "Сериалы",
            notes: [NoteData(term: "hang out", translation: "тусоваться"),
                    NoteData(term: "freeze", translation: "замереть")])))
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        try ReviewService(context: context).apply(grade: .good, to: card)
        ProgressService(context: context).createContract(goal: 10, reward: "пицца")
        context.insert(ProgressSnapshot(date: Date(), matureWords: 1, totalWords: 2))
        try context.save()
        XCTAssertGreaterThan(count(Review.self, in: context), 0)

        try DataEraseService(context: context).eraseDatabase()

        XCTAssertEqual(count(Folder.self, in: context), 0)
        XCTAssertEqual(count(Deck.self, in: context), 0)
        XCTAssertEqual(count(Note.self, in: context), 0)
        XCTAssertEqual(count(Card.self, in: context), 0)
        XCTAssertEqual(count(Review.self, in: context), 0)
        XCTAssertEqual(count(RewardContractEntity.self, in: context), 0)
        XCTAssertEqual(count(ProgressSnapshot.self, in: context), 0)
    }

    func testErasingAnEmptyDatabaseIsFine() throws {
        let context = try TestDB.makeContext()
        XCTAssertNoThrow(try DataEraseService(context: context).eraseDatabase())
        XCTAssertEqual(count(Note.self, in: context), 0)
    }

    func testSettingsAreWiped() throws {
        let suite = "erase-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: SettingsKey.reminderEnabled)
        defaults.set("B2", forKey: SettingsKey.englishLevel)

        DataEraseService.eraseSettings(defaults: defaults, domain: suite)

        XCTAssertNil(defaults.object(forKey: SettingsKey.reminderEnabled))
        XCTAssertNil(defaults.string(forKey: SettingsKey.englishLevel))
    }
}
