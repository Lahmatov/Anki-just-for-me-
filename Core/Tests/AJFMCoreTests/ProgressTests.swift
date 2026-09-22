import XCTest
@testable import AJFMCore

final class RewardContractTests: XCTestCase {

    private func contract(
        goal: Int = 150, baseline: Int = 0, deadline: Date? = nil,
        completed: Bool = false, manual: Bool = false
    ) -> RewardContract {
        RewardContract(
            goal: goal, reward: "диск с игрой",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            baseline: baseline, deadline: deadline,
            completedAt: completed ? Date() : nil,
            hadManualAdjustments: manual)
    }

    func testProgressCountsFromTheBaseline() {
        // Главное в контракте: 150 слов считаются от момента, когда его завели,
        // а не от начала времён — иначе цель выполнена в момент создания.
        let progress = RewardCalculator.progress(
            contract: contract(baseline: 200), currentMatureWords: 260)
        XCTAssertEqual(progress.done, 60)
        XCTAssertEqual(progress.remaining, 90)
        XCTAssertFalse(progress.isReached)
    }

    func testFreshContractStartsAtZero() {
        let progress = RewardCalculator.progress(
            contract: contract(baseline: 200), currentMatureWords: 200)
        XCTAssertEqual(progress.done, 0)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testGoalIsReached() {
        let progress = RewardCalculator.progress(
            contract: contract(goal: 150, baseline: 10), currentMatureWords: 160)
        XCTAssertTrue(progress.isReached)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testOvershootDoesNotExceedFullProgress() {
        let progress = RewardCalculator.progress(
            contract: contract(goal: 100), currentMatureWords: 500)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remaining, 0)
    }

    func testForgettingWordsCannotPushProgressNegative() {
        // Слова могут выпасть из зрелых, если их забыли, — прогресс просто
        // не растёт, но отрицательным не становится.
        let progress = RewardCalculator.progress(
            contract: contract(baseline: 100), currentMatureWords: 80)
        XCTAssertEqual(progress.done, 0)
        XCTAssertEqual(progress.remaining, 150)
    }

    func testDeadlineGivesDailyPace() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = now.addingTimeInterval(10 * 86_400)
        let progress = RewardCalculator.progress(
            contract: contract(goal: 100, deadline: deadline),
            currentMatureWords: 50, now: now)

        XCTAssertEqual(progress.daysLeft, 10)
        XCTAssertEqual(progress.requiredPerDay ?? 0, 5, accuracy: 0.01)
    }

    func testNoPaceWhenGoalAlreadyReached() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let progress = RewardCalculator.progress(
            contract: contract(goal: 10, deadline: now.addingTimeInterval(86_400)),
            currentMatureWords: 50, now: now)
        XCTAssertNil(progress.requiredPerDay)
    }

    func testStatusLines() {
        let inProgress = RewardCalculator.progress(
            contract: contract(), currentMatureWords: 100)
        XCTAssertTrue(RewardCalculator
            .statusLine(contract: contract(), progress: inProgress)
            .contains("50 слов"))

        let reached = RewardCalculator.progress(
            contract: contract(), currentMatureWords: 150)
        XCTAssertTrue(RewardCalculator
            .statusLine(contract: contract(), progress: reached)
            .contains("диск с игрой"))
    }

    func testManualAdjustmentsAreVisibleInTheResult() {
        // Приложение своё, «отметить выученным» соблазнительно — но тогда
        // и награда должна выглядеть иначе.
        let done = contract(completed: true, manual: true)
        let progress = RewardCalculator.progress(contract: done, currentMatureWords: 150)
        XCTAssertTrue(RewardCalculator
            .statusLine(contract: done, progress: progress)
            .contains("правился руками"))
    }

    func testContractSanitizesItsInput() {
        let weird = RewardContract(goal: -5, reward: "x", baseline: -10)
        XCTAssertEqual(weird.goal, 1)
        XCTAssertEqual(weird.baseline, 0)
    }

    func testContractSurvivesJSONRoundTrip() throws {
        let original = contract(goal: 42, baseline: 7, deadline: Date())
        let restored = try JSONDecoder().decode(
            RewardContract.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }
}

final class AchievementTests: XCTestCase {

    func testCatalogIsSmallAndWellFormed() {
        let all = AchievementCatalog.all
        // Полсотни бейджей ни за что обесценивают остальные — держим десяток-полтора.
        XCTAssertGreaterThanOrEqual(all.count, 10)
        XCTAssertLessThanOrEqual(all.count, 15)

        for achievement in all {
            XCTAssertFalse(achievement.title.isEmpty)
            XCTAssertFalse(achievement.detail.isEmpty)
            XCTAssertGreaterThan(achievement.threshold, 0)
        }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "идентификаторы должны быть уникальны")
    }

    func testNothingUnlockedOnEmptyStats() {
        XCTAssertTrue(AchievementCatalog.unlocked(for: LearningStats()).isEmpty)
    }

    func testMatureWordsUnlockInOrder() {
        let stats = LearningStats(matureWords: 60)
        let unlocked = AchievementCatalog.unlocked(for: stats).map(\.id)
        XCTAssertTrue(unlocked.contains("mature-10"))
        XCTAssertTrue(unlocked.contains("mature-50"))
        XCTAssertFalse(unlocked.contains("mature-150"))
    }

    func testCoverageAchievementUsesFraction() {
        XCTAssertFalse(Achievement(
            id: "x", title: "t", detail: "d", metric: .retellCoverage,
            threshold: 0.8, symbol: "s").isUnlocked(by: LearningStats(bestRetellCoverage: 0.7)))
        XCTAssertTrue(Achievement(
            id: "x", title: "t", detail: "d", metric: .retellCoverage,
            threshold: 0.8, symbol: "s").isUnlocked(by: LearningStats(bestRetellCoverage: 0.85)))
    }

    func testProgressTowardsLockedAchievement() throws {
        let achievement = try XCTUnwrap(
            AchievementCatalog.all.first { $0.id == "mature-150" })
        XCTAssertEqual(
            achievement.progress(in: LearningStats(matureWords: 75)), 0.5, accuracy: 0.001)
        XCTAssertEqual(achievement.progress(in: LearningStats(matureWords: 900)), 1)
    }

    func testNextGoalIsTheClosestOne() {
        // Показываем ту цель, до которой ближе всего, — она мотивирует.
        let stats = LearningStats(matureWords: 140, currentStreakDays: 1)
        XCTAssertEqual(AchievementCatalog.next(for: stats)?.id, "mature-150")
    }

    func testNoAchievementRewardsClicking() {
        // Ни одна ачивка не должна выдаваться за количество показанных карточек:
        // такое накликивается за вечер и обесценивает остальные.
        for achievement in AchievementCatalog.all {
            XCTAssertNotEqual(achievement.metric.rawValue, "cardsShown")
        }
    }
}

final class StreakCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func days(_ dates: [Date]) -> Set<Date> {
        StreakCalculator.studyDays(from: dates, cutoffHour: 4, calendar: calendar)
    }

    func testConsecutiveDaysCount() {
        let studied = days([date(9), date(10), date(11)])
        XCTAssertEqual(
            StreakCalculator.currentStreak(
                studyDays: studied, now: date(11, 20), cutoffHour: 4, calendar: calendar),
            3)
    }

    func testTodayNotStudiedYetDoesNotBreakTheStreak() {
        // Утром счёт не должен обнуляться только потому, что день ещё не начат.
        let studied = days([date(9), date(10)])
        XCTAssertEqual(
            StreakCalculator.currentStreak(
                studyDays: studied, now: date(11, 9), cutoffHour: 4, calendar: calendar),
            2)
    }

    func testGapBreaksTheStreak() {
        let studied = days([date(5), date(6), date(9), date(10)])
        XCTAssertEqual(
            StreakCalculator.currentStreak(
                studyDays: studied, now: date(10, 20), cutoffHour: 4, calendar: calendar),
            2)
    }

    func testLateNightSessionCountsAsPreviousDay() {
        // Занятие в 2 ночи 11-го — это вечер 10-го.
        let studied = days([date(9), date(10), date(11, 2)])
        XCTAssertEqual(
            StreakCalculator.currentStreak(
                studyDays: studied, now: date(10, 23), cutoffHour: 4, calendar: calendar),
            2)
    }

    func testEmptyHistoryGivesZero() {
        XCTAssertEqual(
            StreakCalculator.currentStreak(
                studyDays: [], now: date(10), cutoffHour: 4, calendar: calendar),
            0)
    }

    func testWeekProgressCountsFromMonday() {
        // 2026-03-09 — понедельник.
        let studied = days([date(9), date(10), date(12)])
        let progress = StreakCalculator.weekProgress(
            studyDays: studied, target: 5, now: date(13), cutoffHour: 4, calendar: calendar)

        XCTAssertEqual(progress.daysStudied, 3)
        XCTAssertEqual(progress.target, 5)
        XCTAssertFalse(progress.isReached)
        XCTAssertEqual(progress.fraction, 0.6, accuracy: 0.001)
    }

    func testPreviousWeekDoesNotCount() {
        let studied = days([date(2), date(3), date(4), date(5), date(6)])
        let progress = StreakCalculator.weekProgress(
            studyDays: studied, target: 5, now: date(11), cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(progress.daysStudied, 0)
    }

    func testWeeklyGoalCanBeReached() {
        let studied = days([date(9), date(10), date(11), date(12), date(13)])
        let progress = StreakCalculator.weekProgress(
            studyDays: studied, target: 5, now: date(13), cutoffHour: 4, calendar: calendar)
        XCTAssertTrue(progress.isReached)
    }

    func testFreezesAreCountedPerMonth() {
        let used = [date(3), date(7)]
        XCTAssertEqual(
            StreakCalculator.freezesLeft(
                usedDates: used, allowancePerMonth: 2, now: date(20), calendar: calendar),
            0)
        XCTAssertEqual(
            StreakCalculator.freezesLeft(
                usedDates: [date(3)], allowancePerMonth: 2, now: date(20), calendar: calendar),
            1)
    }

    func testFreezesResetNextMonth() {
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        XCTAssertEqual(
            StreakCalculator.freezesLeft(
                usedDates: [lastMonth, lastMonth], allowancePerMonth: 2,
                now: date(10), calendar: calendar),
            2)
    }
}
