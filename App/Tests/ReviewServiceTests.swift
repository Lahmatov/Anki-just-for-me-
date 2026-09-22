import XCTest
import SwiftData
import AJFMCore
@testable import AJFM

@MainActor
final class ReviewServiceTests: XCTestCase {

    private func makeEnvironment(
        settings: AppSettings = AppSettings.default
    ) throws -> (ModelContext, ImportService, ReviewService) {
        let context = try TestDB.makeContext()
        return (context, ImportService(context: context),
                ReviewService(context: context, settings: settings))
    }

    private func words(_ count: Int) -> [NoteData] {
        (1...count).map { NoteData(term: "word\($0)", translation: "слово \($0)") }
    }

    private func importDeck(
        _ importer: ImportService, scheduler: SchedulerID? = nil,
        cardTypes: [CardType]? = [.recognition], count: Int = 3
    ) throws {
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            scheduler: scheduler, cardTypes: cardTypes, notes: words(count))))
    }

    func testFreshlyImportedCardsAreAllDue() throws {
        let (_, importer, service) = try makeEnvironment()
        try importDeck(importer, count: 3)

        let queue = try service.todayQueue()
        XCTAssertEqual(queue.summary.new, 3)
        XCTAssertEqual(queue.cards.count, 3)
    }

    func testNewCardLimitAppliesToTheQueue() throws {
        var settings = AppSettings.default
        settings.newPerDay = 2
        let (_, importer, service) = try makeEnvironment(settings: settings)
        try importDeck(importer, count: 10)

        let queue = try service.todayQueue()
        XCTAssertEqual(queue.cards.count, 2)
        XCTAssertEqual(queue.summary.heldBack, 8)
    }

    func testSiblingsOfOneWordAreBuried() throws {
        let (_, importer, service) = try makeEnvironment()
        try importDeck(importer, cardTypes: [.recognition, .recall, .listening], count: 1)

        let queue = try service.todayQueue()
        XCTAssertEqual(queue.cards.count, 1, "одно слово — одна карточка за сессию")
        XCTAssertEqual(queue.summary.heldBack, 2)
    }

    func testGradingMovesTheCardAndLogsTheReview() throws {
        let (context, importer, service) = try makeEnvironment()
        try importDeck(importer, count: 1)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
        let before = card.due

        let state = try service.apply(grade: .good, to: card, timeSpent: 3.5)

        XCTAssertEqual(state.reps, 1)
        XCTAssertGreaterThan(card.due, before)
        XCTAssertNotEqual(card.state, .new)
        XCTAssertNotNil(card.stability, "FSRS должен записать устойчивость")

        let logs = try context.fetch(FetchDescriptor<Review>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].grade, Grade.good.rawValue)
        XCTAssertEqual(logs[0].algorithm, SchedulerID.fsrs6.rawValue)
        XCTAssertTrue(logs[0].isHonest)
        XCTAssertEqual(logs[0].timeSpent, 3.5, accuracy: 0.001)
    }

    func testDeckAlgorithmIsRespected() throws {
        let (context, importer, service) = try makeEnvironment()
        try importDeck(importer, scheduler: .leitner, count: 1)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)

        try service.apply(grade: .good, to: card)

        XCTAssertEqual(card.box, 1, "коробки Лейтнера, а не устойчивость FSRS")
        XCTAssertNil(card.stability)
        let log = try XCTUnwrap(try context.fetch(FetchDescriptor<Review>()).first)
        XCTAssertEqual(log.algorithm, SchedulerID.leitner.rawValue)
    }

    func testAnsweredCardLeavesTodayQueue() throws {
        let (context, importer, service) = try makeEnvironment()
        try importDeck(importer, count: 1)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)

        // «Легко» выпускает карточку сразу в повторение на несколько дней.
        try service.apply(grade: .easy, to: card)

        XCTAssertTrue(try service.todayQueue().isEmpty)
    }

    func testFailedCardComesBackWithinTheSameSession() throws {
        let (context, importer, service) = try makeEnvironment()
        try importDeck(importer, count: 1)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)

        try service.apply(grade: .again, to: card)
        // Через час забытая карточка обязана снова быть в очереди.
        let later = Date().addingTimeInterval(3600)
        XCTAssertEqual(try service.todayQueue(now: later).cards.count, 1)
    }

    func testPreviewCoversAllGrades() throws {
        let (context, importer, service) = try makeEnvironment()
        try importDeck(importer, count: 1)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)

        let preview = service.preview(for: card)
        XCTAssertEqual(preview.count, 4)
        XCTAssertLessThan(preview[.again] ?? 0, preview[.easy] ?? 0)
    }

    func testRetentionSettingChangesIntervals() throws {
        func intervalAfterEasy(retention: Double) throws -> Double {
            var settings = AppSettings.default
            settings.desiredRetention = retention
            let (context, importer, service) = try makeEnvironment(settings: settings)
            try importDeck(importer, count: 1)
            let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)
            return try service.apply(grade: .easy, to: card).intervalDays
        }
        XCTAssertGreaterThan(
            try intervalAfterEasy(retention: 0.7),
            try intervalAfterEasy(retention: 0.95),
            "низкая планка удержания — более редкие повторения")
    }

    func testDeckQueueIgnoresOtherDecks() throws {
        let (context, importer, service) = try makeEnvironment()
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "Первый", cardTypes: [.recognition], notes: words(2))))
        try importer.apply(try importer.makePlan(from: TestDB.deckFile(
            name: "Второй", cardTypes: [.recognition],
            notes: [NoteData(term: "unique", translation: "уникальное")])))

        let second = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Deck>()).first { $0.name == "Второй" })
        XCTAssertEqual(service.queue(for: second).cards.count, 1)
        XCTAssertEqual(try service.todayQueue().cards.count, 3)
    }

    func testMaturityIsReachedOnlyThroughLongIntervals() throws {
        let (context, importer, service) = try makeEnvironment()
        try importDeck(importer, count: 1)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<Card>()).first)

        var now = Date()
        // Пяти уверенных повторов хватает: интервал доходит до полутора месяцев.
        for _ in 0..<5 {
            try service.apply(grade: .good, to: card, now: now)
            now = card.due
        }
        // Смысл проверки: зрелость нельзя накликать за вечер — она берётся
        // только из реально выросшего интервала.
        XCTAssertTrue(card.isMature)
        XCTAssertGreaterThanOrEqual(card.intervalDays, ReviewState.matureIntervalDays)
    }
}
