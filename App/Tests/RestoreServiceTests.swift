import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class RestoreServiceTests: XCTestCase {

    private func makeEnvironment() throws
        -> (ModelContext, ImportService, ExportService, RestoreService) {
        let context = try TestDB.makeContext()
        return (context, ImportService(context: context),
                ExportService(context: context), RestoreService(context: context))
    }

    private func seed(_ importer: ImportService) throws {
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S03E05", folder: "Сериалы/BB",
            scheduler: .sm2, cardTypes: [.recognition, .recall],
            notes: [
                NoteData(term: "leverage", translation: "рычаг", ipa: "/ˈlevərɪdʒ/"),
                NoteData(term: "to back out", translation: "пойти на попятную"),
            ])))
    }

    func testFullCycleRestoresEverything() throws {
        let (context, importer, exporter, restorer) = try makeEnvironment()
        try seed(importer)

        // Доводим одну карточку до зрелости, чтобы проверить перенос прогресса.
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        card.state = .review
        card.intervalDays = 40
        card.reps = 9
        card.lapses = 2
        card.ease = 2.35
        try context.save()

        let backup = try exporter.makeBackup()
        let data = try BackupCoder.encode(backup)

        // Имитируем новое устройство: пустая база.
        let (freshContext, _, _, freshRestorer) = try makeEnvironment()
        let (parsed, preview) = try freshRestorer.preview(from: data)

        XCTAssertEqual(preview.decks, 1)
        XCTAssertEqual(preview.notes, 2)
        XCTAssertEqual(preview.cards, 4)
        XCTAssertEqual(preview.matureWords, 1)

        let result = try freshRestorer.restore(parsed)
        XCTAssertEqual(result, RestoreService.Result(decks: 1, notes: 2, cards: 4))

        let deck = try XCTUnwrap(try freshContext.fetch(FetchDescriptor<Deck>()).first)
        XCTAssertEqual(deck.name, "S03E05")
        XCTAssertEqual(deck.scheduler, .sm2)
        XCTAssertEqual(deck.cardTypes, [.recognition, .recall])
        XCTAssertEqual(deck.folder?.path, "Сериалы/BB")
        XCTAssertEqual(deck.notes.count, 2)

        let restoredCard = try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<Card>()).first { $0.intervalDays == 40 })
        XCTAssertEqual(restoredCard.state, .review)
        XCTAssertEqual(restoredCard.reps, 9)
        XCTAssertEqual(restoredCard.lapses, 2)
        XCTAssertEqual(restoredCard.ease, 2.35)
        XCTAssertTrue(restoredCard.isMature, "прогресс — единственное, что нельзя набрать заново")
    }

    func testRestoreReplacesExistingContent() throws {
        let (context, importer, exporter, restorer) = try makeEnvironment()
        try seed(importer)
        let backup = try exporter.makeBackup()

        // Добавляем набор, которого в бэкапе нет.
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "Лишний", notes: [NoteData(term: "extra", translation: "лишнее")])))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 2)

        try restorer.restore(backup)

        // Восстановление возвращает состояние на момент бэкапа целиком,
        // а не подмешивает его к текущему.
        let decks = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.name, "S03E05")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 2)
    }

    func testNoOrphansAfterRestore() throws {
        let (context, importer, exporter, restorer) = try makeEnvironment()
        try seed(importer)
        let backup = try exporter.makeBackup()

        try restorer.restore(backup)

        let notes = try context.fetch(FetchDescriptor<Note>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertTrue(notes.allSatisfy { $0.deck != nil }, "слова без набора не должны остаться")
        XCTAssertTrue(cards.allSatisfy { $0.note != nil }, "карточки без слова — тоже")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Folder>()).count, 2)
    }

    func testFoldersAreNotDuplicatedAcrossDecks() throws {
        let (context, importer, exporter, restorer) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S01", folder: "Сериалы/BB",
            notes: [NoteData(term: "one", translation: "раз")])))
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S02", folder: "Сериалы/BB",
            notes: [NoteData(term: "two", translation: "два")])))

        try restorer.restore(try exporter.makeBackup())

        XCTAssertEqual(try context.fetch(FetchDescriptor<Folder>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 2)
    }

    func testEmptyBackupWipesTheBase() throws {
        let (context, importer, _, restorer) = try makeEnvironment()
        try seed(importer)

        try restorer.restore(BackupFile(exportedAt: Date(), decks: []))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).count, 0)
    }

    func testGarbageFileIsRejectedBeforeTouchingTheBase() throws {
        let (context, importer, _, restorer) = try makeEnvironment()
        try seed(importer)

        XCTAssertThrowsError(try restorer.preview(from: Data("не json".utf8)))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 2, "база цела")
    }

    func testDeckFileIsNotAcceptedAsBackup() throws {
        let (_, _, _, restorer) = try makeEnvironment()
        // Набор карточек — другой формат; принимать его за бэкап нельзя.
        XCTAssertThrowsError(try restorer.preview(from: TestDB.deckFile(
            notes: [NoteData(term: "a", translation: "б")])))
    }
}
