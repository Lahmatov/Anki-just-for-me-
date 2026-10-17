import XCTest
@testable import AJFMCore

final class LessonQuizTests: XCTestCase {

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private let notes: [NoteData] = [
        NoteData(term: "comer", translation: "есть", cloze: "Ontem ___ bacalhau."),
        NoteData(term: "beber", translation: "пить", cloze: "Eu ___ café."),
        NoteData(term: "o pequeno-almoço", translation: "завтрак"),
        NoteData(term: "a chávena", translation: "чашка"),
        NoteData(term: "apetecer", translation: "хотеться", cloze: "Apetece-me ___."),
        NoteData(term: "o talho", translation: "мясная лавка"),
    ]

    private func quiz(_ notes: [NoteData], count: Int = 10, seed: UInt64 = 1) -> [QuizQuestion] {
        var generator = Seeded(state: seed)
        return LessonQuiz.make(notes: notes, count: count, using: &generator)
    }

    func testEveryQuestionHasItsAnswerAmongTheChoices() {
        for question in quiz(notes) {
            XCTAssertTrue(question.choices.contains(question.answer), question.prompt)
            XCTAssertEqual(Set(question.choices).count, question.choices.count, "варианты не повторяются")
            XCTAssertGreaterThanOrEqual(question.choices.count, 2)
        }
    }

    func testOneQuestionPerWordAtMost() {
        XCTAssertEqual(quiz(notes).count, notes.count)
        XCTAssertEqual(quiz(notes, count: 3).count, 3)
    }

    /// Неправильные варианты — из того же урока, а не из всего словаря.
    func testWrongChoicesComeFromTheLesson() {
        let terms = Set(notes.map(\.term))
        let translations = Set(notes.map(\.translation))
        for question in quiz(notes) {
            let pool = question.kind == .meaning ? translations : terms
            XCTAssertTrue(Set(question.choices).isSubset(of: pool), "\(question.kind)")
        }
    }

    func testGapQuestionsUseRealGaps() {
        let gaps = (1...20).flatMap { quiz(notes, seed: $0) }.filter { $0.kind == .gap }
        XCTAssertFalse(gaps.isEmpty)
        for gap in gaps { XCTAssertTrue(gap.prompt.contains("___")) }
    }

    func testTooFewWordsMakeNoQuiz() {
        XCTAssertTrue(quiz([]).isEmpty)
        XCTAssertTrue(quiz([notes[0]]).isEmpty)
        XCTAssertTrue(quiz(notes, count: 0).isEmpty)
    }

    func testBlankAndDuplicateWordsAreSkipped() {
        let messy = notes + [NoteData(term: " ", translation: "x"), NoteData(term: "Comer", translation: "есть")]
        XCTAssertEqual(quiz(messy).count, notes.count)
    }

    func testScore() {
        let questions = quiz(notes)
        var answers: [Int: String] = [:]
        for question in questions.prefix(4) { answers[question.id] = question.answer }
        if let wrong = questions.dropFirst(4).first {
            answers[wrong.id] = wrong.choices.first { $0 != wrong.answer }
        }
        XCTAssertEqual(LessonQuiz.score(questions, answers: answers), 4.0 / Double(questions.count),
                       accuracy: 0.0001)
        XCTAssertEqual(LessonQuiz.score([], answers: [:]), 0)
    }

    func testPassMark() {
        XCTAssertTrue(LessonQuiz.passed(0.8))
        XCTAssertTrue(LessonQuiz.passed(1))
        XCTAssertFalse(LessonQuiz.passed(0.79))
    }

    func testSameSeedSameQuiz() {
        XCTAssertEqual(quiz(notes, seed: 7), quiz(notes, seed: 7))
    }
}
