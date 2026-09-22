import XCTest
@testable import AJFMCore

final class OnboardingPlanTests: XCTestCase {

    func testFirstLaunchShowsEverything() {
        let plan = OnboardingPlan.make(
            hasWords: false, needsBetterVoice: true, hasGoal: false, hasReminder: false)
        XCTAssertEqual(plan.steps, OnboardingStep.allCases)
    }

    func testHowItWorksIsAlwaysThere() {
        // Объяснение контура нужно и тому, кто вернулся из настроек:
        // это единственный шаг, который ничего не настраивает, а рассказывает.
        let plan = OnboardingPlan.make(
            hasWords: true, needsBetterVoice: false, hasGoal: true, hasReminder: true)
        XCTAssertEqual(plan.steps, [.howItWorks])
        XCTAssertFalse(plan.isEmpty)
    }

    func testStarterDeckIsSkippedWhenWordsExist() {
        let plan = OnboardingPlan.make(
            hasWords: true, needsBetterVoice: false, hasGoal: false, hasReminder: false)
        XCTAssertFalse(plan.steps.contains(.starterDeck))
    }

    func testVoiceStepOnlyWhenSystemVoiceIsPoor() {
        // Советовать скачать голос, когда хороший уже стоит, — шум.
        let good = OnboardingPlan.make(
            hasWords: false, needsBetterVoice: false, hasGoal: false, hasReminder: false)
        XCTAssertFalse(good.steps.contains(.voice))

        let poor = OnboardingPlan.make(
            hasWords: false, needsBetterVoice: true, hasGoal: false, hasReminder: false)
        XCTAssertTrue(poor.steps.contains(.voice))
    }

    func testGoalAndReminderAreSkippedWhenSet() {
        let plan = OnboardingPlan.make(
            hasWords: false, needsBetterVoice: false, hasGoal: true, hasReminder: true)
        XCTAssertEqual(plan.steps, [.howItWorks, .starterDeck])
    }

    func testStepOrderIsStable() {
        // Порядок продуман: сначала что это такое, потом чем учиться,
        // потом как звучит, и только в конце — зачем и когда.
        let plan = OnboardingPlan.make(
            hasWords: false, needsBetterVoice: true, hasGoal: false, hasReminder: false)
        XCTAssertEqual(
            plan.steps, [.howItWorks, .starterDeck, .voice, .goal, .reminder])
    }

    func testEveryStepHasATitle() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step.rawValue): нет заголовка")
        }
    }

    func testStepIdentifiersAreUnique() {
        let ids = OnboardingStep.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testPlansWithDifferentStepsHaveDifferentIdentifiers() {
        // Идентификатор нужен, чтобы экран показывался заново, когда набор
        // шагов изменился: вернулся из настроек — а часть уже не нужна.
        let full = OnboardingPlan.make(
            hasWords: false, needsBetterVoice: true, hasGoal: false, hasReminder: false)
        let short = OnboardingPlan.make(
            hasWords: true, needsBetterVoice: false, hasGoal: true, hasReminder: true)
        XCTAssertNotEqual(full.id, short.id)
        XCTAssertEqual(short.id, OnboardingStep.howItWorks.rawValue)
    }

    func testFirstLaunchConstantMatchesAllCases() {
        XCTAssertEqual(OnboardingPlan.firstLaunch.steps, OnboardingStep.allCases)
        XCTAssertEqual(OnboardingPlan.firstLaunch.count, OnboardingStep.allCases.count)
    }
}
