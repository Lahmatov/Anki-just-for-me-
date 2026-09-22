import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class OnboardingPlanBuilderTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.reminderEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.reminderEnabled)
    }

    func testEmptyAppGetsStarterDeckStep() throws {
        let context = try TestDB.makeContext()
        let plan = OnboardingPlanBuilder.make(context: context)

        XCTAssertTrue(plan.steps.contains(.howItWorks))
        XCTAssertTrue(plan.steps.contains(.starterDeck), "учить нечего — набор нужен")
        XCTAssertTrue(plan.steps.contains(.goal))
    }

    func testStarterStepDisappearsOnceWordsExist() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            notes: [NoteData(term: "leverage", translation: "рычаг")])))

        let plan = OnboardingPlanBuilder.make(context: context)
        XCTAssertFalse(plan.steps.contains(.starterDeck))
    }

    func testGoalStepDisappearsOnceContractExists() throws {
        let context = try TestDB.makeContext()
        ProgressService(context: context).createContract(goal: 150, reward: "пицца")

        let plan = OnboardingPlanBuilder.make(context: context)
        XCTAssertFalse(plan.steps.contains(.goal))
    }

    func testCompletedContractDoesNotCountAsGoal() throws {
        let context = try TestDB.makeContext()
        let service = ProgressService(context: context)
        service.createContract(goal: 150, reward: "пицца")
        service.complete(try XCTUnwrap(service.activeContract))

        // Награда получена, новой цели нет — предложить её уместно.
        let plan = OnboardingPlanBuilder.make(context: context)
        XCTAssertTrue(plan.steps.contains(.goal))
    }

    func testReminderStepDisappearsWhenEnabled() throws {
        let context = try TestDB.makeContext()
        UserDefaults.standard.set(true, forKey: SettingsKey.reminderEnabled)

        let plan = OnboardingPlanBuilder.make(context: context)
        XCTAssertFalse(plan.steps.contains(.reminder))
    }

    func testFullySetUpAppShowsOnlyTheExplanation() throws {
        let context = try TestDB.makeContext()
        let importer = ImportService(context: context)
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            notes: [NoteData(term: "leverage", translation: "рычаг")])))
        ProgressService(context: context).createContract(goal: 150, reward: "пицца")
        UserDefaults.standard.set(true, forKey: SettingsKey.reminderEnabled)

        let plan = OnboardingPlanBuilder.make(context: context)
        // Вернулся из настроек — листать пустые экраны незачем.
        XCTAssertTrue(plan.steps.contains(.howItWorks))
        XCTAssertFalse(plan.steps.contains(.starterDeck))
        XCTAssertFalse(plan.steps.contains(.goal))
        XCTAssertFalse(plan.steps.contains(.reminder))
    }

    func testPlanIsNeverEmpty() throws {
        let context = try TestDB.makeContext()
        XCTAssertFalse(OnboardingPlanBuilder.make(context: context).isEmpty)
    }
}
