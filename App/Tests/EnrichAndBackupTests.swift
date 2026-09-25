import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class EnrichServiceTests: XCTestCase {

    private func makeEnvironment() throws -> (ModelContext, ImportService, EnrichService) {
        let context = try TestDB.makeContext()
        return (context, ImportService(context: context), EnrichService(context: context))
    }

    private func track(_ lines: [String]) -> SubtitleTrack {
        SubtitleTrack(cues: lines.enumerated().map { index, text in
            SubtitleCue(
                index: index + 1, start: Double(index) * 10,
                end: Double(index) * 10 + 3, text: text)
        })
    }

    func testFillsMissingExamplesFromSubtitles() throws {
        let (context, importer, enricher) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: [
            NoteData(term: "leverage", translation: "рычаг"),
            NoteData(term: "космос", translation: "space"),
        ])))
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)

        let result = enricher.enrich(
            deck: deck, with: track(["You have no leverage at all."]))

        XCTAssertEqual(result.enriched, 1)
        XCTAssertEqual(result.skipped, 1, "слова, которого нет в серии, пропускаем")

        let note = try XCTUnwrap(deck.notes.first { $0.term == "leverage" })
        XCTAssertEqual(note.example, "You have no leverage at all.")
        XCTAssertEqual(note.cloze, "You have no ___ at all.")
    }

    func testExistingExamplesAreKept() throws {
        let (context, importer, enricher) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: [
            NoteData(term: "leverage", translation: "рычаг", example: "Мой пример.")
        ])))
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)

        let result = enricher.enrich(
            deck: deck, with: track(["You have no leverage at all."]))

        XCTAssertEqual(result.enriched, 0)
        XCTAssertEqual(deck.notes.first?.example, "Мой пример.")
    }

    func testOverwriteReplacesExamples() throws {
        let (context, importer, enricher) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: [
            NoteData(term: "leverage", translation: "рычаг", example: "Старый пример.")
        ])))
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)

        enricher.enrich(
            deck: deck, with: track(["You have no leverage at all."]), overwrite: true)
        XCTAssertEqual(deck.notes.first?.example, "You have no leverage at all.")
    }

    func testCountsWordsWithoutExamples() throws {
        let (context, importer, enricher) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: [
            NoteData(term: "one", translation: "раз", example: "Есть пример."),
            NoteData(term: "two", translation: "два"),
            NoteData(term: "three", translation: "три"),
        ])))
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)

        XCTAssertEqual(enricher.notesWithoutExamples(in: deck).count, 2)
    }

    func testEmptySubtitlesChangeNothing() throws {
        let (context, importer, enricher) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: [
            NoteData(term: "leverage", translation: "рычаг")
        ])))
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)

        let result = enricher.enrich(deck: deck, with: SubtitleTrack(cues: []))
        XCTAssertEqual(result.enriched, 0)
        XCTAssertNil(deck.notes.first?.example)
    }
}

@MainActor
final class BackupServiceTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastBackupDate)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastBackupDate)
        if let directory = BackupService.directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testBackupWritesReadableFile() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(notes: [
            NoteData(term: "leverage", translation: "рычаг")
        ])))

        let url = try XCTUnwrap(BackupService(context: context).performBackup())
        let restored = try BackupCoder.decode(try Data(contentsOf: url))

        XCTAssertEqual(restored.noteCount, 1)
        XCTAssertEqual(restored.format, BackupFile.formatID)
    }

    func testWeeklyBackupSkipsIfRecent() throws {
        let context = try TestDB.makeContext()
        let service = BackupService(context: context)

        XCTAssertNotNil(service.backupIfNeeded(), "первый запуск — бэкап нужен")
        XCTAssertNil(service.backupIfNeeded(), "через минуту повторять незачем")
    }

    func testWeeklyBackupRunsAfterAWeek() throws {
        let context = try TestDB.makeContext()
        let service = BackupService(context: context)

        XCTAssertNotNil(service.backupIfNeeded(now: Date()))
        let laterOn = Date().addingTimeInterval(BackupService.interval + 60)
        XCTAssertNotNil(service.backupIfNeeded(now: laterOn))
    }

    func testOldBackupsArePruned() throws {
        let context = try TestDB.makeContext()
        let service = BackupService(context: context)

        // Десять бэкапов подряд — на диске должно остаться восемь.
        for index in 0..<10 {
            service.performBackup(now: Date().addingTimeInterval(Double(index) * 86_400))
        }
        XCTAssertLessThanOrEqual(service.backupCount, 8)
        XCTAssertGreaterThan(service.backupCount, 0)
    }

    func testEmptyDatabaseStillBacksUp() throws {
        let context = try TestDB.makeContext()
        let url = try XCTUnwrap(BackupService(context: context).performBackup())
        XCTAssertEqual(try BackupCoder.decode(try Data(contentsOf: url)).noteCount, 0)
    }
}

final class PromptTemplatesTests: XCTestCase {

    func testNewDeckPromptCarriesSourceAndWords() {
        let prompt = PromptTemplates.newDeck(
            source: "Breaking Bad S03E05", words: ["leverage", "pull off"], language: .russian)

        XCTAssertTrue(prompt.contains("Breaking Bad S03E05"))
        XCTAssertTrue(prompt.contains("leverage, pull off"))
        XCTAssertTrue(prompt.contains("ajfm-deck"))
    }

    func testPromptDemandsExamplesFromTheEpisode() {
        let prompt = PromptTemplates.newDeck(source: "X", words: [], language: .russian)
        // Словарный пример работает хуже фразы из сцены, которую ты видел.
        XCTAssertTrue(prompt.contains("a real line from this episode"))
        XCTAssertTrue(prompt.contains("not a dictionary example"))
    }

    func testPromptCapsDeckSize() {
        XCTAssertTrue(PromptTemplates.newDeck(source: "X", words: [], language: .russian)
            .contains("no more than 30 words"))
    }

    func testEmptyWordListLeavesAPlaceholder() {
        XCTAssertTrue(PromptTemplates.newDeck(source: "X", words: [], language: .russian)
            .contains("<paste the words"))
    }

    func testPromptNamesTheListOfWords() {
        // Из-за этого сломался первый импорт: модель назвала список по-своему.
        XCTAssertTrue(PromptTemplates.newDeck(source: "X", words: [], language: .russian)
            .contains(#"called "notes""#))
    }

    func testTranslationsFollowTheInterfaceLanguage() {
        XCTAssertTrue(PromptTemplates.newDeck(source: "X", words: [], language: .portuguese)
            .contains("European Portuguese"))
        XCTAssertTrue(PromptTemplates.newDeck(source: "X", words: [], language: .english)
            .contains("plain-English definition"))
    }
}
