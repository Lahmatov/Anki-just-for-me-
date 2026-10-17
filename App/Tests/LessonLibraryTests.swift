import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

/// Уроки на настоящей базе (P-69). Правила карты и теста — в тестах ядра.
@MainActor
final class LessonLibraryTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lessonQuizScores)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.lessonQuizScores)
    }

    private func install(_ name: String, folder: String?, words: Int, into context: ModelContext) throws {
        let notes = (1...words).map { NoteData(term: "\(name) w\($0)", translation: "слово \($0)") }
        let file = DeckFile(deck: DeckMeta(name: name, folder: folder), notes: notes)
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: file))
    }

    private func deck(_ name: String, in context: ModelContext) throws -> Deck {
        try XCTUnwrap(LessonLibrary.decks(in: context).first { $0.name == name })
    }

    /// Папка урока — на языке интерфейса в момент создания: узнаём любую.
    func testLessonsAreDecksInTheLessonsFolderInAnyLanguage() throws {
        let context = try TestDB.makeContext()
        try install("Aula 1", folder: "Уроки", words: 2, into: context)
        try install("Aula 2", folder: "Aulas", words: 2, into: context)
        try install("Lesson 3", folder: "Lessons", words: 2, into: context)
        try install("Friends S01E01", folder: "Сериалы/Friends", words: 2, into: context)
        try install("Свободный", folder: nil, words: 2, into: context)
        XCTAssertEqual(Set(LessonLibrary.decks(in: context).map(\.name)), ["Aula 1", "Aula 2", "Lesson 3"])
    }

    func testEmptyBaseHasNoLessons() throws {
        let context = try TestDB.makeContext()
        XCTAssertTrue(LessonLibrary.decks(in: context).isEmpty)
        XCTAssertEqual(LessonLibrary.path(in: context).total, 0)
        XCTAssertNil(LessonLibrary.path(in: context).current)
    }

    func testStepCountsStartedWords() throws {
        let context = try TestDB.makeContext()
        try install("Aula 1", folder: "Aulas", words: 4, into: context)
        let lesson = try deck("Aula 1", in: context)
        for note in lesson.notes.prefix(3) {
            note.cards.first?.stateRaw = LearningState.review.rawValue
        }
        let step = LessonLibrary.step(for: lesson)
        XCTAssertEqual(step.totalWords, 4)
        XCTAssertEqual(step.startedWords, 3)
        XCTAssertNil(step.bestQuiz)
        XCTAssertFalse(step.isDone)
    }

    /// Слабая попытка не отнимает сданный тест.
    func testQuizKeepsTheBestScore() throws {
        let context = try TestDB.makeContext()
        try install("Aula 1", folder: "Aulas", words: 2, into: context)
        let lesson = try deck("Aula 1", in: context)
        XCTAssertTrue(LessonLibrary.record(quiz: 0.9, for: lesson))
        XCTAssertFalse(LessonLibrary.record(quiz: 0.4, for: lesson))
        XCTAssertEqual(LessonLibrary.bestQuiz(for: lesson), 0.9)
    }

    func testLessonIsDoneWithAllWordsStartedAndQuizPassed() throws {
        let context = try TestDB.makeContext()
        try install("Aula 1", folder: "Aulas", words: 2, into: context)
        let lesson = try deck("Aula 1", in: context)
        for note in lesson.notes { note.cards.first?.stateRaw = LearningState.learning.rawValue }
        LessonLibrary.record(quiz: 0.8, for: lesson)
        XCTAssertTrue(LessonLibrary.step(for: lesson).isDone)
        XCTAssertEqual(LessonLibrary.path(in: context).doneCount, 1)
    }

    func testNotesKeepTheirFields() throws {
        let context = try TestDB.makeContext()
        let file = DeckFile(deck: DeckMeta(name: "Aula", folder: "Aulas"), notes: [
            NoteData(term: "comer", translation: "есть", partOfSpeech: .verb, cloze: "Eu ___ pão."),
        ])
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: file))
        let notes = LessonLibrary.notes(of: try deck("Aula", in: context))
        XCTAssertEqual(notes.first?.partOfSpeech, .verb)
        XCTAssertEqual(notes.first?.cloze, "Eu ___ pão.")
    }
}
