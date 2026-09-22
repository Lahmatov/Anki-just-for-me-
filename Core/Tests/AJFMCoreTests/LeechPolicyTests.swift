import XCTest
@testable import AJFMCore

final class LeechPolicyTests: XCTestCase {

    func testThresholdDetection() {
        XCTAssertFalse(LeechPolicy.isLeech(lapses: 4))
        XCTAssertTrue(LeechPolicy.isLeech(lapses: 5))
        XCTAssertTrue(LeechPolicy.isLeech(lapses: 12))
    }

    func testCustomThreshold() {
        XCTAssertTrue(LeechPolicy.isLeech(lapses: 3, threshold: 3))
        XCTAssertFalse(LeechPolicy.isLeech(lapses: 3, threshold: 8))
    }

    func testSeverityIsShareOfFailures() {
        XCTAssertEqual(LeechPolicy.severity(lapses: 5, reps: 10), 0.5, accuracy: 0.001)
        XCTAssertEqual(LeechPolicy.severity(lapses: 1, reps: 100), 0.01, accuracy: 0.001)
    }

    func testSeverityHandlesNoReviews() {
        XCTAssertEqual(LeechPolicy.severity(lapses: 0, reps: 0), 0)
    }

    func testMissingContextIsTheFirstSuspect() {
        // Слово без примера — самая частая причина, и чинится проще всего.
        let advice = LeechPolicy.advice(lapses: 6, hasExample: false, termWordCount: 1)
        XCTAssertTrue(advice.contains("пример"))
        XCTAssertTrue(advice.contains("субтитры"))
    }

    func testLongPhraseGetsItsOwnAdvice() {
        let advice = LeechPolicy.advice(lapses: 6, hasExample: true, termWordCount: 7)
        XCTAssertTrue(advice.contains("Разбей"))
    }

    func testDesperateCaseSuggestsRewritingOrDropping() {
        let advice = LeechPolicy.advice(lapses: 12, hasExample: true, termWordCount: 1)
        XCTAssertTrue(advice.contains("Перепиши") || advice.contains("отложи"))
    }

    func testDefaultAdviceMentionsConfusableWords() {
        let advice = LeechPolicy.advice(lapses: 6, hasExample: true, termWordCount: 1)
        XCTAssertTrue(advice.contains("путается"))
    }

    func testRussianPluralsAreCorrect() {
        // Мелочь, но «забыто 2 раз» бросается в глаза каждый раз.
        XCTAssertEqual(LeechPolicy.summary(lapses: 1), "Забыто 1 раз")
        XCTAssertEqual(LeechPolicy.summary(lapses: 2), "Забыто 2 раза")
        XCTAssertEqual(LeechPolicy.summary(lapses: 5), "Забыто 5 раз")
        XCTAssertEqual(LeechPolicy.summary(lapses: 11), "Забыто 11 раз")
        XCTAssertEqual(LeechPolicy.summary(lapses: 21), "Забыто 21 раз")
        XCTAssertEqual(LeechPolicy.summary(lapses: 112), "Забыто 112 раз")
        XCTAssertEqual(LeechPolicy.summary(lapses: 122), "Забыто 122 раза")
        XCTAssertEqual(LeechPolicy.summary(lapses: 3), "Забыто 3 раза")
    }
}
