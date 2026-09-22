import XCTest
@testable import AJFMCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

final class FSRS6BehaviourTests: XCTestCase {
    private let scheduler = FSRS6Scheduler(enableFuzzing: false)

    func testNewCardLeavesNewState() {
        let result = scheduler.review(ReviewState(), grade: .good, now: now)
        XCTAssertNotEqual(result.state, .new)
        XCTAssertEqual(result.reps, 1)
        XCTAssertNotNil(result.stability)
        XCTAssertNotNil(result.difficulty)
    }

    func testEasyGraduatesImmediatelyButGoodDoesNot() {
        let easy = scheduler.review(ReviewState(), grade: .easy, now: now)
        XCTAssertEqual(easy.state, .review, "«Легко» выпускает карточку сразу")

        let good = scheduler.review(ReviewState(), grade: .good, now: now)
        XCTAssertEqual(good.state, .learning, "«Хорошо» оставляет её на шагах заучивания")
    }

    func testDifficultyStaysInRange() {
        // Загоняем сложность в оба предела и проверяем, что её там удержали.
        var hardest = ReviewState()
        for _ in 0..<40 {
            hardest = scheduler.review(hardest, grade: .again, now: hardest.due)
        }
        XCTAssertLessThanOrEqual(hardest.difficulty ?? 0, FSRS6Scheduler.difficultyMax)
        XCTAssertGreaterThanOrEqual(hardest.difficulty ?? 0, FSRS6Scheduler.difficultyMin)

        var easiest = ReviewState()
        for _ in 0..<40 {
            easiest = scheduler.review(easiest, grade: .easy, now: easiest.due)
        }
        XCTAssertGreaterThanOrEqual(easiest.difficulty ?? 0, FSRS6Scheduler.difficultyMin)
    }

    func testLapseIsCountedOnlyFromReviewState() {
        var card = scheduler.review(ReviewState(), grade: .easy, now: now)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.lapses, 0)

        card = scheduler.review(card, grade: .again, now: card.due)
        XCTAssertEqual(card.lapses, 1, "провал в фазе повторения — это провал")
        XCTAssertEqual(card.state, .relearning)

        card = scheduler.review(card, grade: .again, now: card.due)
        XCTAssertEqual(card.lapses, 1, "повторный промах в переучивании не удваивает счёт")
    }

    func testLowerRetentionGivesLongerIntervals() {
        func intervalAfterGraduating(retention: Double) -> Double {
            let scheduler = FSRS6Scheduler(
                desiredRetention: retention, enableFuzzing: false)
            let card = scheduler.review(ReviewState(), grade: .easy, now: now)
            return card.intervalDays
        }
        // Чем ниже планка «помнить на момент показа», тем реже повторения.
        XCTAssertGreaterThan(
            intervalAfterGraduating(retention: 0.7),
            intervalAfterGraduating(retention: 0.95))
    }

    func testRetrievabilityFallsOverTime() {
        let card = scheduler.review(ReviewState(), grade: .easy, now: now)
        let fresh = scheduler.retrievability(card, now: card.lastReview ?? now)
        let later = scheduler.retrievability(
            card, now: (card.lastReview ?? now).addingTimeInterval(30 * day))

        XCTAssertEqual(fresh, 1.0, accuracy: 0.001, "сразу после повтора помним точно")
        XCTAssertLessThan(later, fresh)
        XCTAssertGreaterThan(later, 0)
    }

    func testRetrievabilityIsNinetyPercentAfterOneStability() {
        // Смысл устойчивости: ровно через S дней вероятность вспомнить равна 90%.
        var card = ReviewState()
        card.stability = 10
        card.lastReview = now
        let r = scheduler.retrievability(card, now: now.addingTimeInterval(10 * day))
        XCTAssertEqual(r, 0.9, accuracy: 0.0001)
    }

    func testUnknownCardHasZeroRetrievability() {
        XCTAssertEqual(scheduler.retrievability(ReviewState(), now: now), 0)
    }

    func testPreviewCoversAllGradesAndIsOrdered() {
        let card = scheduler.review(ReviewState(), grade: .easy, now: now)
        let preview = scheduler.preview(card, now: card.due)

        XCTAssertEqual(preview.count, 4)
        XCTAssertLessThan(
            preview[.again] ?? 0, preview[.good] ?? 0,
            "после провала карточка возвращается раньше")
        XCTAssertLessThan(
            preview[.good] ?? 0, preview[.easy] ?? 0,
            "«Легко» откладывает дальше «Хорошо»")
    }

    func testBadParameterCountFallsBackToDefaults() {
        let broken = FSRS6Scheduler(parameters: [1, 2, 3])
        XCTAssertEqual(broken.parameters, FSRS6Scheduler.defaultParameters)
    }

    func testFuzzingKeepsIntervalNearby() {
        let fuzzy = FSRS6Scheduler(enableFuzzing: true)
        var card = ReviewState(state: .review, intervalDays: 30)
        card.stability = 60
        card.difficulty = 5
        card.lastReview = now.addingTimeInterval(-30 * day)

        for _ in 0..<50 {
            let result = fuzzy.review(card, grade: .good, now: now)
            // Разброс нужен, чтобы карточки не слипались, но не должен уводить далеко.
            XCTAssertGreaterThan(result.intervalDays, 1)
            XCTAssertLessThan(result.intervalDays, 400)
        }
    }
}

final class SM2SchedulerTests: XCTestCase {
    private let scheduler = SM2Scheduler()

    func testGoodWalksThroughLearningStepsThenGraduates() {
        var card = scheduler.review(ReviewState(), grade: .good, now: now)
        XCTAssertEqual(card.state, .learning)
        XCTAssertEqual(card.step, 1)

        card = scheduler.review(card, grade: .good, now: card.due)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.intervalDays, 1)
    }

    func testEaseDropsOnHardAndNeverGoesBelowMinimum() {
        var card = scheduler.review(ReviewState(), grade: .easy, now: now)
        XCTAssertEqual(card.ease ?? 0, SM2Scheduler.defaultEase, accuracy: 0.0001)

        for _ in 0..<30 {
            card = scheduler.review(card, grade: .hard, now: card.due)
        }
        XCTAssertEqual(card.ease ?? 0, SM2Scheduler.minimumEase, accuracy: 0.0001)
    }

    func testGoodMultipliesIntervalByEase() {
        var card = ReviewState(state: .review, intervalDays: 10)
        card.ease = 2.5
        card = scheduler.review(card, grade: .good, now: now)
        XCTAssertEqual(card.intervalDays, 25, "10 дней × 2.5")
    }

    func testAgainSendsCardToRelearning() {
        var card = ReviewState(state: .review, intervalDays: 50)
        card.ease = 2.5
        card = scheduler.review(card, grade: .again, now: now)

        XCTAssertEqual(card.state, .relearning)
        XCTAssertEqual(card.lapses, 1)
        XCTAssertEqual(card.ease ?? 0, 2.3, accuracy: 0.0001)
        XCTAssertLessThan(card.intervalDays, 1, "возврат через минуты, а не дни")
    }

    func testGraduatingAfterLapseStartsOver() {
        var card = ReviewState(state: .review, intervalDays: 50)
        card.ease = 2.5
        card = scheduler.review(card, grade: .again, now: now)
        card = scheduler.review(card, grade: .good, now: card.due)

        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.intervalDays, 1, "накопленный интервал после провала сгорает")
    }

    func testIntervalsAreWholeDaysInReview() {
        var card = ReviewState(state: .review, intervalDays: 3)
        card.ease = 2.5
        card = scheduler.review(card, grade: .good, now: now)
        // 3 × 2.5 = 7.5 — дробный интервал должен стать целым числом суток,
        // иначе повторения расползаются внутри дня.
        XCTAssertEqual(card.intervalDays, 8)
    }

    func testMaximumIntervalIsRespected() {
        let capped = SM2Scheduler(maximumIntervalDays: 100)
        var card = ReviewState(state: .review, intervalDays: 90)
        card.ease = 2.5
        card = capped.review(card, grade: .easy, now: now)
        XCTAssertEqual(card.intervalDays, 100)
    }
}

final class LeitnerSchedulerTests: XCTestCase {
    private let scheduler = LeitnerScheduler()

    func testGoodMovesUpOneBox() {
        var card = scheduler.review(ReviewState(), grade: .good, now: now)
        XCTAssertEqual(card.box, 1)
        XCTAssertEqual(card.intervalDays, 3)

        card = scheduler.review(card, grade: .good, now: card.due)
        XCTAssertEqual(card.box, 2)
        XCTAssertEqual(card.intervalDays, 7)
    }

    func testEasyJumpsTwoBoxes() {
        let card = scheduler.review(ReviewState(), grade: .easy, now: now)
        XCTAssertEqual(card.box, 2)
    }

    func testHardKeepsTheSameBox() {
        var card = scheduler.review(ReviewState(), grade: .good, now: now)
        let box = card.box
        card = scheduler.review(card, grade: .hard, now: card.due)
        XCTAssertEqual(card.box, box)
    }

    func testAgainReturnsToFirstBox() {
        var card = ReviewState(state: .review, intervalDays: 30)
        card.box = 4
        card = scheduler.review(card, grade: .again, now: now)
        XCTAssertEqual(card.box, 0)
        XCTAssertEqual(card.intervalDays, 1)
        XCTAssertEqual(card.lapses, 1)
    }

    func testLastBoxIsTheCeiling() {
        var card = ReviewState()
        for _ in 0..<10 {
            card = scheduler.review(card, grade: .easy, now: card.due)
        }
        XCTAssertEqual(card.box, scheduler.boxCount - 1)
        XCTAssertEqual(card.intervalDays, 30)
    }

    func testEmptyBoxListFallsBackToDefault() {
        let fallback = LeitnerScheduler(boxIntervalDays: [])
        XCTAssertEqual(fallback.boxCount, 5)
    }
}

final class CramSchedulerTests: XCTestCase {
    private let scheduler = CramScheduler()

    func testTwoGoodAnswersInARowSettleTheCard() {
        var card = scheduler.review(ReviewState(), grade: .good, now: now)
        XCTAssertEqual(card.state, .learning)
        XCTAssertEqual(card.streak, 1)

        card = scheduler.review(card, grade: .good, now: card.due)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.intervalDays, 1)
    }

    func testEasyClosesTheGoalAtOnce() {
        let card = scheduler.review(ReviewState(), grade: .easy, now: now)
        XCTAssertEqual(card.state, .review)
        XCTAssertGreaterThanOrEqual(card.streak ?? 0, scheduler.requiredStreak)
    }

    func testAgainResetsTheStreak() {
        var card = scheduler.review(ReviewState(), grade: .good, now: now)
        card = scheduler.review(card, grade: .again, now: card.due)
        XCTAssertEqual(card.streak, 0)
        XCTAssertEqual(card.state, .learning)
        XCTAssertEqual(card.due.timeIntervalSince(card.lastReview ?? now), 60, accuracy: 1)
    }

    func testHardKeepsStreakButComesBackSoon() {
        var card = scheduler.review(ReviewState(), grade: .good, now: now)
        let streak = card.streak
        card = scheduler.review(card, grade: .hard, now: card.due)
        XCTAssertEqual(card.streak, streak, "трудный ответ не двигает серию")
        XCTAssertEqual(card.state, .learning)
    }
}

final class SchedulerFactoryTests: XCTestCase {
    func testFactoryReturnsMatchingScheduler() {
        for id in SchedulerID.allCases {
            XCTAssertEqual(SchedulerFactory.make(id).id, id)
        }
    }

    func testEverySchedulerAdvancesANewCard() {
        for id in SchedulerID.allCases {
            let scheduler = SchedulerFactory.make(id)
            let card = scheduler.review(ReviewState(), grade: .good, now: now)
            XCTAssertGreaterThan(
                card.due, now, "\(id.rawValue): карточка должна уехать в будущее")
            XCTAssertEqual(card.reps, 1, "\(id.rawValue): повтор должен засчитаться")
            XCTAssertNotNil(card.lastReview, "\(id.rawValue): дата повтора обязательна")
        }
    }

    func testEverySchedulerPreviewsAllFourGrades() {
        for id in SchedulerID.allCases {
            XCTAssertEqual(SchedulerFactory.make(id).preview(ReviewState(), now: now).count, 4)
        }
    }
}

final class IntervalFormatterTests: XCTestCase {
    func testFormatsAcrossScales() {
        XCTAssertEqual(IntervalFormatter.short(30), "<1 мин")
        XCTAssertEqual(IntervalFormatter.short(600), "10 мин")
        XCTAssertEqual(IntervalFormatter.short(3 * 3600), "3 ч")
        XCTAssertEqual(IntervalFormatter.short(5 * day), "5 дн")
        XCTAssertEqual(IntervalFormatter.short(90 * day), "3.0 мес")
        XCTAssertEqual(IntervalFormatter.short(730 * day), "2.0 г")
    }
}

final class ReviewStateTests: XCTestCase {
    func testMaturityNeedsReviewStateAndFullInterval() {
        XCTAssertFalse(ReviewState(state: .learning, intervalDays: 100).isMature)
        XCTAssertFalse(ReviewState(state: .review, intervalDays: 20.9).isMature)
        XCTAssertTrue(ReviewState(state: .review, intervalDays: 21).isMature)
    }

    func testElapsedDaysRoundsDown() {
        let start = now
        XCTAssertEqual(elapsedDays(from: start, to: start.addingTimeInterval(0.9 * day)), 0)
        XCTAssertEqual(elapsedDays(from: start, to: start.addingTimeInterval(1.9 * day)), 1)
        XCTAssertEqual(elapsedDays(from: start, to: start.addingTimeInterval(-0.1 * day)), -1)
    }

    func testStateSurvivesJSONRoundTrip() throws {
        var state = ReviewState(state: .review, intervalDays: 12, reps: 5, lapses: 2)
        state.stability = 34.5
        state.difficulty = 6.1
        state.ease = 2.3
        state.box = 3
        state.streak = 1

        let restored = try JSONDecoder().decode(
            ReviewState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
    }
}
