import XCTest
@testable import AJFMCore

final class StudyDayTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testEveningBelongsToTheSameDay() {
        let start = ReviewQueueBuilder.studyDayStart(
            for: date(10, 23), cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(start, date(10, 4))
    }

    func testAfterMidnightStillCountsAsYesterday() {
        // Ночная сессия в 2:30 — это всё ещё вчерашний учебный день,
        // иначе счёт дней рвётся на ровном месте.
        let start = ReviewQueueBuilder.studyDayStart(
            for: date(11, 2, 30), cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(start, date(10, 4))
    }

    func testCutoffHourItselfStartsNewDay() {
        let start = ReviewQueueBuilder.studyDayStart(
            for: date(11, 4), cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(start, date(11, 4))
    }

    func testDayEndIsExactlyTwentyFourHoursLater() {
        let now = date(10, 15)
        let start = ReviewQueueBuilder.studyDayStart(for: now, cutoffHour: 4, calendar: calendar)
        let end = ReviewQueueBuilder.studyDayEnd(for: now, cutoffHour: 4, calendar: calendar)
        XCTAssertEqual(end.timeIntervalSince(start), 86_400)
    }
}

final class ReviewQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func card(
        _ id: String, note: String? = nil, type: CardType = .recognition,
        state: LearningState = .review, dueIn: TimeInterval = -3600
    ) -> QueueCard {
        QueueCard(
            id: id, noteID: note ?? id, type: type, state: state,
            due: now.addingTimeInterval(dueIn), addedAt: now)
    }

    private func build(_ cards: [QueueCard], config: QueueConfig = QueueConfig()) -> ReviewQueue {
        ReviewQueueBuilder.build(cards: cards, config: config, now: now)
    }

    func testDueCardsGetIntoTheQueue() {
        let queue = build([card("a"), card("b")])
        XCTAssertEqual(queue.cards.count, 2)
        XCTAssertEqual(queue.summary.review, 2)
    }

    func testCardsDueLaterAreHeldBack() {
        let queue = build([card("today"), card("next-week", dueIn: 7 * day)])
        XCTAssertEqual(queue.cards.map(\.id), ["today"])
        XCTAssertEqual(queue.summary.heldBack, 1)
    }

    func testLearningCardIsNotShownBeforeItsTime() {
        // Шаги заучивания идут минутами, поэтому смотрим на текущий момент.
        let queue = build([card("soon", state: .learning, dueIn: 300)])
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.summary.heldBack, 1)
    }

    func testLearningCardsComeFirst() {
        let queue = build([
            card("review-1"),
            card("learning", state: .learning, dueIn: -60),
            card("review-2"),
        ])
        XCTAssertEqual(queue.cards.first?.id, "learning")
    }

    func testOverdueCardsComeBeforeRecentOnes() {
        let queue = build([
            card("recent", dueIn: -60),
            card("ancient", dueIn: -30 * day),
        ])
        XCTAssertEqual(queue.cards.map(\.id), ["ancient", "recent"])
    }

    func testNewCardLimitIsRespected() {
        let cards = (1...30).map { card("new-\($0)", state: .new, dueIn: 0) }
        let queue = build(cards, config: QueueConfig(newPerDay: 5))
        XCTAssertEqual(queue.summary.new, 5)
        XCTAssertEqual(queue.summary.heldBack, 25)
    }

    func testReviewLimitIsRespected() {
        let cards = (1...50).map { card("review-\($0)") }
        let queue = build(cards, config: QueueConfig(reviewsPerDay: 10))
        XCTAssertEqual(queue.summary.review, 10)
        XCTAssertEqual(queue.summary.heldBack, 40)
    }

    func testZeroNewPerDayMeansOnlyReviews() {
        let queue = build(
            [card("r"), card("n", state: .new, dueIn: 0)],
            config: QueueConfig(newPerDay: 0))
        XCTAssertEqual(queue.cards.map(\.id), ["r"])
    }

    // MARK: - Захоронение братьев

    func testSiblingsAreBuried() {
        // Пять карточек одного слова за сессию — верный способ обмануть себя.
        let cards = CardType.allCases.enumerated().map { index, type in
            card("card-\(index)", note: "same-word", type: type)
        }
        let queue = build(cards)
        XCTAssertEqual(queue.cards.count, 1)
        XCTAssertEqual(queue.summary.heldBack, cards.count - 1)
    }

    func testDifferentWordsAreNotBuried() {
        let queue = build([
            card("a", note: "word-1"),
            card("b", note: "word-2"),
        ])
        XCTAssertEqual(queue.cards.count, 2)
    }

    func testBuryingCanBeTurnedOff() {
        let cards = [
            card("a", note: "same"),
            card("b", note: "same"),
        ]
        let queue = build(cards, config: QueueConfig(burySiblings: false))
        XCTAssertEqual(queue.cards.count, 2)
    }

    func testBuryingKeepsTheEarliestSibling() {
        let queue = build([
            card("later", note: "same", dueIn: -60),
            card("earlier", note: "same", dueIn: -10 * day),
        ])
        XCTAssertEqual(queue.cards.map(\.id), ["earlier"])
    }

    // MARK: - Перемешивание

    func testNewCardsAreSpreadThroughTheQueue() {
        let reviews = (1...8).map { card("r\($0)") }
        let fresh = (1...2).map { card("n\($0)", state: .new, dueIn: 0) }
        let queue = build(reviews + fresh)

        let positions = queue.cards.enumerated()
            .filter { $0.element.state == .new }
            .map(\.offset)

        XCTAssertEqual(positions.count, 2)
        // Новые не должны свалиться в самый конец, где внимания уже нет.
        XCTAssertLessThan(positions.last ?? 99, queue.cards.count - 1)
        XCTAssertGreaterThan(positions.first ?? 0, 0, "и не должны идти все сразу")
    }

    func testInterleavingKeepsEveryCard() {
        let reviews = (1...7).map { card("r\($0)") }
        let fresh = (1...3).map { card("n\($0)", state: .new, dueIn: 0) }
        let mixed = ReviewQueueBuilder.interleave(reviews, fresh)

        XCTAssertEqual(mixed.count, 10)
        XCTAssertEqual(Set(mixed.map(\.id)), Set((reviews + fresh).map(\.id)))
    }

    func testInterleavingHandlesEmptySides() {
        let reviews = [card("r")]
        let fresh = [card("n", state: .new)]
        XCTAssertEqual(ReviewQueueBuilder.interleave(reviews, []).map(\.id), ["r"])
        XCTAssertEqual(ReviewQueueBuilder.interleave([], fresh).map(\.id), ["n"])
        XCTAssertTrue(ReviewQueueBuilder.interleave([], []).isEmpty)
    }

    func testEmptyInputGivesEmptyQueue() {
        let queue = build([])
        XCTAssertTrue(queue.isEmpty)
        XCTAssertTrue(queue.summary.isEmpty)
        XCTAssertEqual(queue.summary.heldBack, 0)
    }

    func testSummaryCountsMatchTheCards() {
        let queue = build([
            card("l", note: "1", state: .learning, dueIn: -60),
            card("r", note: "2"),
            card("n", note: "3", state: .new, dueIn: 0),
        ])
        XCTAssertEqual(queue.summary.learning, 1)
        XCTAssertEqual(queue.summary.review, 1)
        XCTAssertEqual(queue.summary.new, 1)
        XCTAssertEqual(queue.summary.total, queue.cards.count)
    }
}
