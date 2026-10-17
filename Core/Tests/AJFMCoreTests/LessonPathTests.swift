import XCTest
@testable import AJFMCore

final class LessonPathTests: XCTestCase {

    private func step(_ id: String, day: Double, total: Int = 10, started: Int = 0,
                      quiz: Double? = nil) -> LessonStep {
        LessonStep(id: id, name: "Aula \(id)", createdAt: Date(timeIntervalSince1970: day * 86_400),
                   totalWords: total, startedWords: started, bestQuiz: quiz)
    }

    func testLessonIsDoneOnlyWithAllWordsAndAPassedQuiz() {
        XCTAssertTrue(step("1", day: 1, started: 10, quiz: 0.8).isDone)
        XCTAssertFalse(step("1", day: 1, started: 10, quiz: 0.7).isDone, "тест не сдан")
        XCTAssertFalse(step("1", day: 1, started: 9, quiz: 1).isDone, "не все слова")
        XCTAssertFalse(step("1", day: 1, started: 10).isDone, "теста не было")
        XCTAssertFalse(step("1", day: 1, total: 0, started: 0, quiz: 1).isDone, "пустой урок")
    }

    func testStepsGoInTheOrderTheyWereAdded() {
        let path = LessonPath(steps: [step("b", day: 3), step("a", day: 1), step("c", day: 2)])
        XCTAssertEqual(path.steps.map(\.id), ["a", "c", "b"])
    }

    func testCurrentIsTheFirstUnfinishedLesson() {
        let path = LessonPath(steps: [step("1", day: 1, started: 10, quiz: 1),
                                      step("2", day: 2, started: 3), step("3", day: 3)])
        XCTAssertEqual(path.current?.id, "2")
        XCTAssertEqual(path.doneCount, 1)
        XCTAssertEqual(path.total, 3)
    }

    func testAllDoneHasNoCurrent() {
        XCTAssertNil(LessonPath(steps: [step("1", day: 1, started: 10, quiz: 0.9)]).current)
        XCTAssertNil(LessonPath(steps: []).current)
    }

    func testDuplicatesAreDropped() {
        XCTAssertEqual(LessonPath(steps: [step("1", day: 1), step("1", day: 2)]).total, 1)
    }

    func testFractionCountsWordsAndQuiz() {
        XCTAssertEqual(step("1", day: 1, started: 5).fraction, 0.35, accuracy: 0.0001)
        XCTAssertEqual(step("1", day: 1, started: 10, quiz: 0.9).fraction, 1, accuracy: 0.0001)
        XCTAssertEqual(step("1", day: 1, total: 0).fraction, 0)
    }

    func testBadNumbersAreClamped() {
        let odd = LessonStep(id: "x", name: "x", createdAt: Date(), totalWords: 5, startedWords: 9,
                             bestQuiz: 1.7)
        XCTAssertEqual(odd.startedWords, 5)
        XCTAssertEqual(odd.bestQuiz, 1)
        XCTAssertEqual(LessonStep(id: "y", name: "y", createdAt: Date(), totalWords: -1,
                                  startedWords: -3).totalWords, 0)
    }
}
