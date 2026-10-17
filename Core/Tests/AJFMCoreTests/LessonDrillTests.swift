import XCTest
@testable import AJFMCore

final class LessonDrillTests: XCTestCase {

    private let notes: [NoteData] = [
        NoteData(term: "comer", translation: "есть", partOfSpeech: .verb,
                 example: "Ontem comi bacalhau.", exampleTranslation: "Вчера я ел треску.",
                 cloze: "Ontem ___ bacalhau."),
        NoteData(term: "a chávena", translation: "чашка", partOfSpeech: .noun),
        NoteData(term: "levantar-se", translation: "вставать", partOfSpeech: .verb,
                 example: String(repeating: "muito ", count: 40)),
        NoteData(term: "estar a + infinitivo", translation: "действие в процессе", partOfSpeech: .other),
        NoteData(term: "Comer", translation: "дубль"),
        NoteData(term: "  ", translation: "пусто"),
    ]

    func testTranslationAsksForTheWordByItsTranslation() {
        let items = LessonDrill.items(notes: notes, mode: .translation)
        XCTAssertEqual(items.map(\.answer), ["comer", "a chávena", "levantar-se", "estar a + infinitivo"])
        XCTAssertEqual(items.first?.prompt, "есть")
        XCTAssertEqual(items.map(\.id), [0, 1, 2, 3])
    }

    func testClozeOnlyFromRealGaps() {
        let items = LessonDrill.items(notes: notes, mode: .cloze)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].prompt, "Ontem ___ bacalhau.")
        XCTAssertEqual(items[0].hint, "есть")
    }

    /// Диктуется пример; слишком длинный пример — уже изложение, диктуем слово.
    func testDictationUsesTheExampleWhenItIsShort() {
        let items = LessonDrill.items(notes: notes, mode: .dictation)
        XCTAssertEqual(items[0].spoken, "Ontem comi bacalhau.")
        XCTAssertEqual(items[0].answer, "Ontem comi bacalhau.")
        XCTAssertEqual(items[0].hint, "Вчера я ел треску.")
        XCTAssertEqual(items[0].prompt, "", "на экране — ничего: диктант на слух")
        XCTAssertEqual(items[1].spoken, "a chávena")
        XCTAssertEqual(items[1].hint, "чашка")
        XCTAssertEqual(items[2].spoken, "levantar-se")
    }

    func testPronunciationSaysEveryTerm() {
        XCTAssertEqual(LessonDrill.items(notes: notes, mode: .pronunciation).map(\.spoken),
                       ["comer", "a chávena", "levantar-se", "estar a + infinitivo"])
    }

    func testAvailableModesSkipEmptyTrainers() {
        let withoutGaps = [NoteData(term: "casa", translation: "дом")]
        XCTAssertEqual(LessonDrill.availableModes(notes: withoutGaps), [.translation, .dictation, .pronunciation])
        XCTAssertTrue(LessonDrill.availableModes(notes: []).isEmpty)
    }

    func testEveryModeHasATitle() {
        for mode in DrillMode.allCases { XCTAssertFalse(mode.title.isEmpty) }
    }
}

final class ConjugationDrillTests: XCTestCase {

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private let notes: [NoteData] = [
        NoteData(term: "comer", translation: "есть", partOfSpeech: .verb),
        NoteData(term: "o lugar", translation: "место", partOfSpeech: .noun),
        NoteData(term: "lugar", translation: "место (без пометки)"),
        NoteData(term: "atrair", translation: "привлекать", partOfSpeech: .verb),
        NoteData(term: "levantar-se", translation: "вставать", partOfSpeech: .verb),
        NoteData(term: "Comer", translation: "дубль", partOfSpeech: .verb),
    ]

    /// Только глаголы, и только те, что правило умеет спрягать.
    func testVerbsAreTheConjugatableVerbsOfTheLesson() {
        XCTAssertEqual(ConjugationDrill.verbs(notes: notes, language: .portuguese), ["comer", "levantar-se"])
    }

    func testTasksAnswerFromTheTable() {
        var generator = Seeded(state: 3)
        let tasks = ConjugationDrill.make(verbs: ["comer", "levantar-se"], language: .portuguese,
                                          using: &generator)
        XCTAssertEqual(tasks.count, 8, "2 глагола × 2 времени × 2 лица")
        for task in tasks {
            let form = task.table.forms.first { $0.person == task.person }
            XCTAssertEqual(form?.form, task.answer)
            XCTAssertEqual(task.table.tense, task.tense)
        }
        XCTAssertEqual(tasks.map(\.id), Array(0..<8))
    }

    func testCountLimitsTheTasks() {
        var generator = Seeded(state: 1)
        XCTAssertEqual(ConjugationDrill.make(verbs: ["comer", "falar", "partir"], language: .portuguese,
                                             count: 5, using: &generator).count, 5)
        XCTAssertTrue(ConjugationDrill.make(verbs: [], language: .italian, using: &generator).isEmpty)
        XCTAssertTrue(ConjugationDrill.make(verbs: ["comer"], language: .portuguese, count: -1,
                                            using: &generator).isEmpty)
    }
}

final class LessonFolderTests: XCTestCase {
    func testTheLessonFolderIsRecognisedInEveryLanguage() {
        let saved = Loc.language
        defer { Loc.language = saved }
        for language in AppLanguage.allCases {
            Loc.language = language
            XCTAssertTrue(DeckRequest.lessonFolderNames.contains(DeckRequest.lessonFolder))
            XCTAssertTrue(DeckRequest.isLessonFolder(DeckRequest.lessonFolder))
            XCTAssertTrue(DeckRequest.isLessonFolder(DeckRequest.lessonFolder + "/A2"))
        }
    }

    func testOtherFoldersAreNotLessons() {
        XCTAssertFalse(DeckRequest.isLessonFolder(nil))
        XCTAssertFalse(DeckRequest.isLessonFolder(""))
        XCTAssertFalse(DeckRequest.isLessonFolder("Claude"))
        XCTAssertFalse(DeckRequest.isLessonFolder("Friends/Aulas"))
    }
}
