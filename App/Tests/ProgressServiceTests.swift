import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class ProgressServiceTests: XCTestCase {

    private func makeEnvironment() throws -> (ModelContext, ImportService, ProgressService) {
        let context = try TestDB.makeContext()
        return (context, ImportService(context: context),
                ProgressService(context: context, cutoffHour: 4))
    }

    private func importWords(_ importer: ImportService, count: Int, types: [CardType]) throws {
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            cardTypes: types,
            notes: (1...count).map { NoteData(term: "word\($0)", translation: "слово \($0)") })))
    }

    private func makeMature(_ cards: [Card]) {
        for card in cards {
            card.state = .review
            card.intervalDays = ReviewState.matureIntervalDays + 5
        }
    }

    func testEmptyDatabaseHasNoProgress() throws {
        let (_, _, service) = try makeEnvironment()
        XCTAssertEqual(service.matureWordCount(), 0)
        XCTAssertEqual(service.stats().matureWords, 0)
        XCTAssertNil(service.activeContract)
    }

    func testMatureCountIsPerWordNotPerCard() throws {
        let (context, importer, service) = try makeEnvironment()
        // Одно слово с пятью карточками — это всё равно одно выученное слово.
        try importWords(importer, count: 1, types: [.recognition, .recall, .listening])
        makeMature(try context.fetch(FetchDescriptor<Card>()))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).count, 3)
        XCTAssertEqual(service.matureWordCount(), 1, "иначе награда утраивается на ровном месте")
    }

    func testYoungCardsDoNotCount() throws {
        let (context, importer, service) = try makeEnvironment()
        try importWords(importer, count: 3, types: [.recognition])
        let cards = try context.fetch(FetchDescriptor<Card>())
        cards[0].state = .review
        cards[0].intervalDays = ReviewState.matureIntervalDays - 1
        try context.save()

        XCTAssertEqual(service.matureWordCount(), 0)
    }

    // MARK: - Контракты

    func testContractStartsFromCurrentProgress() throws {
        let (context, importer, service) = try makeEnvironment()
        try importWords(importer, count: 5, types: [.recognition])
        makeMature(try context.fetch(FetchDescriptor<Card>()))
        try context.save()

        service.createContract(goal: 10, reward: "пицца")
        let contract = try XCTUnwrap(service.activeContract)

        // Пять слов уже выучены — цель должна считаться от них, а не с нуля,
        // иначе контракт выполнен в момент создания.
        XCTAssertEqual(contract.baseline, 5)
        let progress = RewardCalculator.progress(
            contract: contract, currentMatureWords: service.matureWordCount())
        XCTAssertEqual(progress.done, 0)
        XCTAssertFalse(progress.isReached)
    }

    func testProgressGrowsAsWordsMature() throws {
        let (context, importer, service) = try makeEnvironment()
        try importWords(importer, count: 10, types: [.recognition])
        service.createContract(goal: 5, reward: "диск")

        makeMature(Array(try context.fetch(FetchDescriptor<Card>()).prefix(3)))
        try context.save()

        let contract = try XCTUnwrap(service.activeContract)
        let progress = RewardCalculator.progress(
            contract: contract, currentMatureWords: service.matureWordCount())
        XCTAssertEqual(progress.done, 3)
        XCTAssertEqual(progress.remaining, 2)
    }

    func testCompletingContractFreesTheSlot() throws {
        let (_, _, service) = try makeEnvironment()
        service.createContract(goal: 10, reward: "пицца")
        let contract = try XCTUnwrap(service.activeContract)

        service.complete(contract)
        XCTAssertNil(service.activeContract)
        XCTAssertEqual(service.contracts().count, 1)
        XCTAssertTrue(service.contracts()[0].isCompleted)
    }

    func testManualAdjustmentIsRecorded() throws {
        let (_, _, service) = try makeEnvironment()
        service.createContract(goal: 10, reward: "пицца")

        service.markManualAdjustment()
        // Приложение своё, и соблазн «отметить выученным» велик — но тогда
        // и награда должна выглядеть иначе.
        XCTAssertTrue(try XCTUnwrap(service.activeContract).hadManualAdjustments)
    }

    func testContractCanBeDeleted() throws {
        let (_, _, service) = try makeEnvironment()
        service.createContract(goal: 10, reward: "пицца")
        service.delete(try XCTUnwrap(service.activeContract))
        XCTAssertTrue(service.contracts().isEmpty)
    }

    // MARK: - Статистика

    func testOnlyHonestReviewsCount() throws {
        let (context, importer, service) = try makeEnvironment()
        try importWords(importer, count: 1, types: [.recognition])
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)

        context.insert(Review(card: card, grade: 3, timeSpent: 1, algorithm: "fsrs6"))
        context.insert(Review(
            card: card, grade: 3, timeSpent: 1, algorithm: "fsrs6", isHonest: false))
        try context.save()

        XCTAssertEqual(service.stats().honestReviews, 1, "правки руками в зачёт не идут")
    }

    func testStatsSeeRetellHistory() throws {
        let (context, _, service) = try makeEnvironment()
        let report = RetellReport(
            understanding: .init(correct: [], incorrect: [], missed: [], coverage: 0.85),
            language: .init(grammar: [], vocabulary: [], fluencyNote: nil, suggestedWords: []),
            topPriorities: [])
        context.insert(RetellSession(
            episodeTitle: "S01E01", transcript: "…", report: report,
            cost: 0.1, model: "claude-opus-5"))
        try context.save()

        let stats = service.stats()
        XCTAssertEqual(stats.retellCount, 1)
        XCTAssertEqual(stats.bestRetellCoverage, 0.85, accuracy: 0.001)
    }

    func testAchievementsUnlockFromRealProgress() throws {
        let (context, importer, service) = try makeEnvironment()
        try importWords(importer, count: 12, types: [.recognition])
        makeMature(try context.fetch(FetchDescriptor<Card>()))
        try context.save()

        let unlocked = AchievementCatalog.unlocked(for: service.stats()).map(\.id)
        XCTAssertTrue(unlocked.contains("mature-10"))
        XCTAssertFalse(unlocked.contains("mature-50"))
    }

    func testWeekProgressUsesHonestReviewDays() throws {
        let (context, importer, service) = try makeEnvironment()
        try importWords(importer, count: 1, types: [.recognition])
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        context.insert(Review(card: card, grade: 3, timeSpent: 1, algorithm: "fsrs6"))
        try context.save()

        let week = service.weekProgress(target: 5)
        XCTAssertGreaterThanOrEqual(week.daysStudied, 1)
        XCTAssertEqual(week.target, 5)
    }
}
