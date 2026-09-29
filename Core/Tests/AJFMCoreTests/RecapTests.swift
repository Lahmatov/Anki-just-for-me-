import XCTest
@testable import AJFMCore

final class RecapTests: XCTestCase {

    // MARK: - Прогресс

    func testFreshRecapStartsWithWords() {
        let progress = RecapProgress()
        XCTAssertEqual(progress.next, .words)
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testStepsGoFromEasyToHard() {
        XCTAssertEqual(RecapStep.allCases, [.words, .questions, .retell])
    }

    func testNextSkipsDoneStepsInOrder() {
        var progress = RecapProgress()
        progress.complete(.words)
        XCTAssertEqual(progress.next, .questions)
        progress.complete(.questions)
        XCTAssertEqual(progress.next, .retell)
    }

    func testStepsDoneOutOfOrderStillCount() {
        // Пересказать можно и без слов: порядок советует, а не запирает.
        var progress = RecapProgress()
        progress.complete(.retell)
        XCTAssertEqual(progress.next, .words)
        XCTAssertEqual(progress.fraction, 1.0 / 3, accuracy: 0.0001)
    }

    func testAllStepsCompleteTheRecap() {
        var progress = RecapProgress()
        RecapStep.allCases.forEach { progress.complete($0) }
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.next)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testCompletingTwiceCountsOnce() {
        var progress = RecapProgress()
        progress.complete(.words)
        progress.complete(.words)
        XCTAssertEqual(progress.fraction, 1.0 / 3, accuracy: 0.0001)
    }

    // MARK: - Хранение

    func testStoredRoundTrips() {
        var progress = RecapProgress()
        progress.complete(.retell)
        progress.complete(.words)
        XCTAssertEqual(progress.stored, ["words", "retell"], "порядок — как у шагов")
        XCTAssertEqual(RecapProgress(stored: progress.stored), progress)
    }

    func testUnknownStoredStepsAreIgnored() {
        let progress = RecapProgress(stored: ["words", "karaoke", ""])
        XCTAssertEqual(progress.done, [.words])
    }

    func testStorageKeyIsPerEpisode() {
        XCTAssertEqual(RecapPlan.storageKey(showID: 431, season: 1, episode: 3), "recap.431.1x3")
        XCTAssertNotEqual(RecapPlan.storageKey(showID: 431, season: 1, episode: 3),
                          RecapPlan.storageKey(showID: 431, season: 1, episode: 4))
    }

    func testDeckSourceMatchesCatalogAndServer() {
        // Тот же вид, что у LocalCatalog.source и deckFile на сервере.
        XCTAssertEqual(RecapPlan.deckSource(showName: "Friends", season: 1, episode: 3), "Friends S01E03")
        XCTAssertEqual(RecapPlan.deckSource(showName: "Lost", season: 2, episode: 12), "Lost S02E12")
    }

    // MARK: - Пять слов

    private func card(_ id: String, note: String) -> QueueCard {
        QueueCard(id: id, noteID: note, type: .recognition, state: .new, due: .distantPast)
    }

    func testLimitCountsWordsNotCards() {
        let cards = [card("a1", note: "a"), card("a2", note: "a"), card("b1", note: "b"),
                     card("c1", note: "c"), card("b2", note: "b")]
        let limited = RecapPlan.limitCards(cards, to: 2)
        XCTAssertEqual(limited.map(\.id), ["a1", "a2", "b1", "b2"],
                       "обе карточки слова остаются вместе, третьего слова нет")
    }

    func testNoLimitKeepsEverything() {
        let cards = (0..<8).map { card("c\($0)", note: "n\($0)") }
        XCTAssertEqual(RecapPlan.limitCards(cards, to: nil), cards)
    }

    func testLimitLargerThanQueueKeepsEverything() {
        let cards = [card("a", note: "a")]
        XCTAssertEqual(RecapPlan.limitCards(cards, to: RecapPlan.words), cards)
    }

    func testZeroOrNegativeLimitGivesNothing() {
        let cards = [card("a", note: "a")]
        XCTAssertEqual(RecapPlan.limitCards(cards, to: 0), [])
        XCTAssertEqual(RecapPlan.limitCards(cards, to: -3), [])
    }

    func testEmptyQueueStaysEmpty() {
        XCTAssertEqual(RecapPlan.limitCards([], to: 5), [])
    }

    // MARK: - Короткий разговор

    private func turns(answers: Int) -> [EpisodeDiscussion.Turn] {
        (0..<answers).flatMap { index in
            [EpisodeDiscussion.Turn(speaker: .monchik, text: "Q\(index)"),
             EpisodeDiscussion.Turn(speaker: .learner, text: "A\(index)")]
        }
    }

    func testShortChatEndsAfterThreeAnswers() {
        XCTAssertFalse(EpisodeDiscussion.isLastTurn(turns(answers: 2), limit: EpisodeDiscussion.recapQuestions))
        XCTAssertTrue(EpisodeDiscussion.isLastTurn(turns(answers: 3), limit: EpisodeDiscussion.recapQuestions))
        XCTAssertFalse(EpisodeDiscussion.isLastTurn(turns(answers: 3)), "обычный разговор — шесть")
    }

    func testShortChatAsksModelToSayGoodbye() {
        let messages = EpisodeDiscussion.messages(for: turns(answers: 3), limit: 3)
        XCTAssertTrue(messages.last?.text.contains("last answer") ?? false)
    }

    func testChatLimitIsClamped() {
        XCTAssertEqual(EpisodeDiscussion.clampedLimit(0), 1)
        XCTAssertEqual(EpisodeDiscussion.clampedLimit(99), EpisodeDiscussion.maxLearnerTurns)
        XCTAssertEqual(EpisodeDiscussion.clampedLimit(3), 3)
    }

    func testDiscussBodySendsQuestionsOnlyWhenShort() throws {
        let short = BackendAPI.DiscussBody(showId: 1, season: 1, episode: 1, language: .russian,
                                           level: nil, turns: [], retelling: nil, questions: 3)
        let full = BackendAPI.DiscussBody(showId: 1, season: 1, episode: 1, language: .russian,
                                          level: nil, turns: [], retelling: nil)
        let encode = { (body: BackendAPI.DiscussBody) in
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        }
        XCTAssertEqual(try encode(short)?["questions"] as? Int, 3)
        XCTAssertNil(try encode(full)?["questions"], "старый сервер не знает поля — не шлём зря")
    }
}
