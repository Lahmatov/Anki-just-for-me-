import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class EntitiesTests: XCTestCase {

    // MARK: - Folder

    func testFolderPathBuildsFromRoot() throws {
        let context = try TestDB.makeContext()
        let root = Folder(name: "Сериалы")
        let child = Folder(name: "Breaking Bad")
        context.insert(root)
        context.insert(child)
        child.parent = root

        XCTAssertEqual(root.path, "Сериалы")
        XCTAssertEqual(child.path, "Сериалы/Breaking Bad")
    }

    func testFolderCountsNotesRecursively() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S01", folder: "Сериалы/BB",
            notes: [NoteData(term: "one", translation: "раз")])))
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "S02", folder: "Сериалы",
            notes: [NoteData(term: "two", translation: "два"),
                    NoteData(term: "three", translation: "три")])))

        let root = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Folder>()).first { $0.name == "Сериалы" })
        // Два слова лежат в самой папке, одно — во вложенной.
        XCTAssertEqual(root.totalNoteCount, 3)
    }

    func testDeletingFolderRemovesItsDecksAndCards() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            folder: "Сериалы/BB", cardTypes: [.recognition, .recall],
            notes: [NoteData(term: "one", translation: "раз")])))

        let root = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Folder>()).first { $0.name == "Сериалы" })
        context.delete(root)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Folder>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).count, 0)
    }

    // MARK: - Card

    /// «Выучено» — единая метрика для наград и статистики, решение P-4.
    /// Если она поедет, вместе с ней поедут все контракты на награды.
    func testMaturityRequiresBothReviewStateAndInterval() throws {
        let context = try TestDB.makeContext()
        let card = Card(type: .recall)
        context.insert(card)

        XCTAssertFalse(card.isMature, "новая карточка зрелой быть не может")

        card.state = .review
        card.intervalDays = Card.matureIntervalDays - 0.1
        XCTAssertFalse(card.isMature, "интервал ещё не дотянул до порога")

        card.intervalDays = Card.matureIntervalDays
        XCTAssertTrue(card.isMature, "ровно на пороге карточка уже зрелая")

        card.state = .relearning
        XCTAssertFalse(card.isMature, "провал сбрасывает зрелость даже при большом интервале")
    }

    func testUnknownRawValuesFallBackInsteadOfCrashing() throws {
        let context = try TestDB.makeContext()
        let card = Card(type: .listening)
        context.insert(card)
        // Такое возможно после отката на старую версию приложения.
        card.typeRaw = "telepathy"
        card.stateRaw = "quantum"

        XCTAssertEqual(card.type, .recognition)
        XCTAssertEqual(card.state, .new)
    }

    // MARK: - Note

    func testNoteRoundTripsThroughNoteData() throws {
        let context = try TestDB.makeContext()
        let original = NoteData(
            term: "to pull off",
            translation: "провернуть",
            ipa: "/pʊl ɔːf/",
            partOfSpeech: .phrasalVerb,
            example: "You pulled it off.",
            exampleTranslation: "Ты это провернул.",
            cloze: "You ___ it ___.",
            synonyms: ["manage"],
            note: "Отделяемый глагол.",
            tags: ["phrasal", "s03e05"],
            difficulty: .medium,
            audio: "pull-off.m4a")

        let note = Note(data: original)
        context.insert(note)

        XCTAssertEqual(note.asNoteData, original)
    }

    func testNoteTrimsWhitespaceAndStoresNormalizedForm() throws {
        let context = try TestDB.makeContext()
        let note = Note(data: NoteData(term: "  The Leverage  ", translation: "  рычаг  "))
        context.insert(note)

        XCTAssertEqual(note.term, "The Leverage")
        XCTAssertEqual(note.translation, "рычаг")
        XCTAssertEqual(note.normalizedTerm, "leverage")
    }

    func testEmptyCollectionsBecomeNilInExport() throws {
        let context = try TestDB.makeContext()
        let note = Note(data: NoteData(term: "word", translation: "слово"))
        context.insert(note)

        // Пустые массивы не должны попадать в файл — иначе он обрастает мусором.
        XCTAssertNil(note.asNoteData.tags)
        XCTAssertNil(note.asNoteData.synonyms)
    }

    // MARK: - Deck

    func testDeckStoresSchedulerAndCardTypesAsRawValues() throws {
        let context = try TestDB.makeContext()
        let deck = Deck(name: "X", scheduler: .leitner, cardTypes: [.spelling, .pronunciation])
        context.insert(deck)

        XCTAssertEqual(deck.schedulerRaw, "leitner")
        XCTAssertEqual(deck.cardTypesRaw, ["spelling", "pronunciation"])

        deck.scheduler = .sm2
        XCTAssertEqual(deck.schedulerRaw, "sm2")
        XCTAssertEqual(deck.scheduler, .sm2)
    }

    func testUnknownSchedulerFallsBackToDefault() throws {
        let context = try TestDB.makeContext()
        let deck = Deck(name: "X", scheduler: .sm2, cardTypes: [])
        context.insert(deck)
        deck.schedulerRaw = "supermemo-17"

        XCTAssertEqual(deck.scheduler, .fsrs6)
    }
}
