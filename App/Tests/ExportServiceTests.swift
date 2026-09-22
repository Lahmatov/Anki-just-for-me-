import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class ExportServiceTests: XCTestCase {
    private func makeEnvironment() throws -> (ModelContext, ImportService, ExportService) {
        let context = try TestDB.makeContext()
        return (context, ImportService(context: context), ExportService(context: context))
    }

    private let sampleNotes = [
        NoteData(
            term: "leverage",
            translation: "рычаг давления",
            ipa: "/ˈlevərɪdʒ/",
            example: "You have no leverage.",
            exampleTranslation: "У тебя нет козырей.",
            tags: ["business"]),
        NoteData(term: "to back out", translation: "пойти на попятную")
    ]

    func testBackupContainsEverythingThatWasImported() throws {
        let (_, importer, exporter) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S03E05", folder: "Сериалы/BB",
            cardTypes: [.recognition, .recall], notes: sampleNotes)))

        let backup = try exporter.makeBackup()

        XCTAssertEqual(backup.decks.count, 1)
        XCTAssertEqual(backup.noteCount, 2)
        let deck = try XCTUnwrap(backup.decks.first)
        XCTAssertEqual(deck.name, "S03E05")
        XCTAssertEqual(deck.folder, "Сериалы/BB")
        XCTAssertEqual(deck.cardTypes, [.recognition, .recall])
        XCTAssertEqual(deck.notes.flatMap(\.cards).count, 4)
    }

    func testBackupKeepsOptionalNoteFields() throws {
        let (_, importer, exporter) = try makeEnvironment()
        try importer.apply(try importer.makePlan(
            from: TestDB.deckFile(notes: sampleNotes)))

        let backup = try exporter.makeBackup()
        let note = try XCTUnwrap(backup.decks.first?.notes.first)
        XCTAssertEqual(note.data.ipa, "/ˈlevərɪdʒ/")
        XCTAssertEqual(note.data.example, "You have no leverage.")
        XCTAssertEqual(note.data.tags, ["business"])
    }

    func testBackupCapturesCardProgress() throws {
        let (context, importer, exporter) = try makeEnvironment()
        try importer.apply(try importer.makePlan(
            from: TestDB.deckFile(cardTypes: [.recall], notes: [sampleNotes[0]])))

        // Имитируем состояние карточки, дожившей до зрелости.
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        card.state = .review
        card.intervalDays = 30
        card.reps = 9
        card.lapses = 2
        card.stability = 42.0
        card.difficulty = 6.5
        try context.save()

        let restored = try BackupCoder.decode(try BackupCoder.encode(try exporter.makeBackup()))
        let backupCard = try XCTUnwrap(restored.decks.first?.notes.first?.cards.first)
        XCTAssertEqual(backupCard.review.state, .review)
        XCTAssertEqual(backupCard.review.intervalDays, 30)
        XCTAssertEqual(backupCard.review.reps, 9)
        XCTAssertEqual(backupCard.review.lapses, 2)
        XCTAssertEqual(backupCard.review.stability, 42.0)
        XCTAssertEqual(backupCard.review.difficulty, 6.5)
        XCTAssertTrue(backupCard.review.isMature, "30 дней — слово в долгосрочной памяти")
    }

    func testEmptyDatabaseExportsWithoutCrashing() throws {
        let (_, _, exporter) = try makeEnvironment()
        let backup = try exporter.makeBackup()
        XCTAssertTrue(backup.decks.isEmpty)
        XCTAssertEqual(backup.noteCount, 0)
    }

    func testBackupFileIsWrittenAndReadable() throws {
        let (_, importer, exporter) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: sampleNotes)))

        let url = try exporter.writeBackupFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let restored = try BackupCoder.decode(try Data(contentsOf: url))
        XCTAssertEqual(restored.noteCount, 2)
        XCTAssertEqual(restored.format, BackupFile.formatID)
    }

    /// Главный сценарий: набор, выгруженный из приложения, снова в него импортируется.
    func testExportedDeckCanBeImportedBack() throws {
        let (context, importer, exporter) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S03E05", folder: "Сериалы/BB",
            scheduler: .sm2, cardTypes: [.listening], notes: sampleNotes)))

        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)
        let url = try exporter.writeDeckFile(deck)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try DeckParser.parse(data: try Data(contentsOf: url))
        XCTAssertEqual(file.deck.name, "S03E05")
        XCTAssertEqual(file.deck.folder, "Сериалы/BB")
        XCTAssertEqual(file.deck.scheduler, .sm2)
        XCTAssertEqual(file.deck.cardTypes, [.listening])
        XCTAssertEqual(file.notes.map(\.term), ["leverage", "to back out"])
        XCTAssertEqual(file.notes[0].ipa, "/ˈlevərɪdʒ/")

        // И повторный импорт того же файла целиком распознаётся как дубли.
        let plan = try importer.makePlan(from: try Data(contentsOf: url))
        XCTAssertTrue(plan.newNotes.isEmpty)
        XCTAssertEqual(plan.duplicates.count, 2)
    }

    func testDeckFileNameIsSafeForFileSystem() throws {
        let (context, importer, exporter) = try makeEnvironment()
        try importer.apply(try importer.makePlan(
            from: TestDB.deckFile(name: "Сериал: 1/2 «тест»", notes: sampleNotes)))

        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)
        let url = try exporter.writeDeckFile(deck)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertFalse(url.lastPathComponent.contains(":"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
