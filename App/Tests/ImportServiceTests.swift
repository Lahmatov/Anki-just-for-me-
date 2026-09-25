import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class ImportServiceTests: XCTestCase {
    private func makeEnvironment() throws -> (ModelContext, ImportService) {
        let context = try TestDB.makeContext()
        return (context, ImportService(context: context))
    }

    private func notes(_ terms: String...) -> [NoteData] {
        terms.map { NoteData(term: $0, translation: "перевод \($0)") }
    }

    func testImportCreatesDeckNotesAndCards() throws {
        let (context, service) = try makeEnvironment()
        let data = TestDB.deckFile(
            name: "Breaking Bad S03E05",
            cardTypes: [.recognition, .recall, .listening],
            notes: notes("leverage", "to pull off"))

        let result = try service.apply(try service.makePlan(from: data))

        XCTAssertEqual(result.addedNotes, 2)
        XCTAssertEqual(result.addedCards, 6)

        let decks = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks[0].name, "Breaking Bad S03E05")
        XCTAssertEqual(decks[0].notes.count, 2)
        XCTAssertEqual(decks[0].notes.reduce(0) { $0 + $1.cards.count }, 6)
    }

    func testNewCardsAreDueImmediately() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(from: TestDB.deckFile(notes: notes("word"))))
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        XCTAssertEqual(card.state, .new)
        XCTAssertEqual(card.reps, 0)
        XCTAssertFalse(card.isMature)
        XCTAssertLessThanOrEqual(card.due.timeIntervalSinceNow, 1)
    }

    func testImportCreatesFolderHierarchy() throws {
        let (context, service) = try makeEnvironment()
        let data = TestDB.deckFile(folder: "Сериалы/Breaking Bad", notes: notes("word"))
        try service.apply(try service.makePlan(from: data))

        let folders = try context.fetch(FetchDescriptor<Folder>())
        XCTAssertEqual(folders.count, 2)

        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)
        XCTAssertEqual(deck.folder?.name, "Breaking Bad")
        XCTAssertEqual(deck.folder?.path, "Сериалы/Breaking Bad")
    }

    func testSecondImportReusesExistingFolders() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(name: "S01", folder: "Сериалы/BB", notes: notes("one"))))
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(name: "S02", folder: "Сериалы/BB", notes: notes("two"))))

        // Папки должны переиспользоваться, а не плодиться копиями.
        XCTAssertEqual(try context.fetch(FetchDescriptor<Folder>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 2)
    }

    func testSameFolderNameUnderDifferentParentsStaysSeparate() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(name: "A", folder: "Сериалы/Season 1", notes: notes("one"))))
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(name: "B", folder: "Книги/Season 1", notes: notes("two"))))

        let seasons = try context.fetch(FetchDescriptor<Folder>()).filter { $0.name == "Season 1" }
        XCTAssertEqual(seasons.count, 2)
        XCTAssertEqual(Set(seasons.map(\.path)), ["Сериалы/Season 1", "Книги/Season 1"])
    }

    func testClozeCardSkippedWhenNoClozeField() throws {
        let (_, service) = try makeEnvironment()
        let data = TestDB.deckFile(
            cardTypes: [.recognition, .cloze],
            notes: [
                NoteData(term: "with", translation: "с", cloze: "I am ___ you."),
                NoteData(term: "without", translation: "без")
            ])
        let result = try service.apply(try service.makePlan(from: data))

        // У первого слова две карточки, у второго — только узнавание.
        XCTAssertEqual(result.addedNotes, 2)
        XCTAssertEqual(result.addedCards, 3)
    }

    func testDuplicateAgainstExistingDeckIsSkipped() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(name: "Старый", notes: notes("leverage"))))

        let plan = try service.makePlan(
            from: TestDB.deckFile(name: "Новый", notes: notes("To Leverage", "fresh")))
        XCTAssertEqual(plan.newNotes.count, 1)
        XCTAssertEqual(plan.duplicates.first?.existingDeckName, "Старый")

        let result = try service.apply(plan)
        XCTAssertEqual(result.addedNotes, 1)
        XCTAssertEqual(result.skippedDuplicates, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 2)
    }

    func testDuplicateAddedWhenExplicitlyRequested() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(name: "Старый", notes: notes("leverage"))))

        let plan = try service.makePlan(
            from: TestDB.deckFile(name: "Новый", notes: notes("leverage")))
        let result = try service.apply(plan, includeDuplicates: true)

        XCTAssertEqual(result.addedNotes, 1)
        XCTAssertEqual(result.skippedDuplicates, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 2)
    }

    func testDuplicateInsideFileIsNeverAddedTwice() throws {
        let (context, service) = try makeEnvironment()
        let plan = try service.makePlan(
            from: TestDB.deckFile(notes: notes("pull off", "To Pull Off")))
        // Даже с явным разрешением дубль из самого файла добавляться не должен.
        let result = try service.apply(plan, includeDuplicates: true)
        XCTAssertEqual(result.addedNotes, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 1)
    }

    func testNormalizedTermIsStoredForFutureDeduplication() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(
            from: TestDB.deckFile(notes: notes("  To Pull Off  "))))
        let note = try XCTUnwrap(try context.fetch(FetchDescriptor<Note>()).first)
        XCTAssertEqual(note.term, "To Pull Off")
        XCTAssertEqual(note.normalizedTerm, "pull off")
    }

    func testDefaultsApplyWhenDeckOmitsSettings() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(from: TestDB.deckFile(notes: notes("word"))))
        let deck = try XCTUnwrap(try context.fetch(FetchDescriptor<Deck>()).first)
        XCTAssertEqual(deck.scheduler, .fsrs6)
        XCTAssertEqual(deck.cardTypes, ImportPlanner.defaultCardTypes)
        XCTAssertNil(deck.folder)
    }

    func testGarbageInputThrowsBeforeTouchingDatabase() throws {
        let (context, service) = try makeEnvironment()
        XCTAssertThrowsError(try service.makePlan(from: "вот твой набор карточек!"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 0)
    }

    func testForeignFormatIsRejected() throws {
        let (_, service) = try makeEnvironment()
        let data = Data(#"{"format":"quizlet","version":1,"deck":{"name":"X"},"notes":[]}"#.utf8)
        XCTAssertThrowsError(try service.makePlan(from: data)) { error in
            XCTAssertEqual(error as? DeckParseError, .wrongFormat(found: "quizlet"))
        }
    }

    // MARK: - Набор по запросу

    func testPlanFromDeckFileMarksExistingWordsAsDuplicates() throws {
        let (_, service) = try makeEnvironment()
        try service.apply(try service.makePlan(from: TestDB.deckFile(notes: notes("leverage"))))

        let generated = DeckFile(
            deck: DeckMeta(name: "От Claude", folder: DeckRequest.folder),
            notes: notes("leverage", "turn out"))
        let plan = try service.makePlan(from: generated)

        XCTAssertEqual(plan.newNotes.map(\.term), ["turn out"])
        XCTAssertEqual(plan.duplicates.map(\.note.term), ["leverage"])
    }

    func testRecentTermsComeNewestFirstAndAreCapped() throws {
        let (context, service) = try makeEnvironment()
        try service.apply(try service.makePlan(from: TestDB.deckFile(
            name: "A", notes: notes("old1", "old2", "old3"))))
        let notesInBase = try context.fetch(FetchDescriptor<Note>())
        for (offset, note) in notesInBase.enumerated() {
            note.createdAt = Date(timeIntervalSince1970: Double(offset))
        }
        let newest = try XCTUnwrap(notesInBase.last)
        try context.save()

        let recent = service.recentTerms(limit: 2)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first, newest.term)
    }

    func testRecentTermsOfEmptyBase() throws {
        let (_, service) = try makeEnvironment()
        XCTAssertEqual(service.recentTerms(limit: 10), [])
    }
}
