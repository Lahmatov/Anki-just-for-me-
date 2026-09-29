import XCTest
@testable import AJFMCore

final class BackendAPITests: XCTestCase {

    override func setUp() {
        super.setUp()
        Loc.language = .russian
    }

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    // MARK: - Запросы

    func testDeckBodyHasTheFieldsTheServerExpects() throws {
        let body = try json(BackendAPI.DeckBody(
            showId: 431, season: 1, episode: 3, language: .portuguese, level: .b1,
            wordCount: 20, knownTerms: ["hello"], subtitles: "  "))
        XCTAssertEqual(body["showId"] as? Int, 431)
        XCTAssertEqual(body["language"] as? String, "pt")
        XCTAssertEqual(body["level"] as? String, "B1")
        XCTAssertEqual(body["knownTerms"] as? [String], ["hello"])
        XCTAssertNil(body["subtitles"], "пустые субтитры не отправляются")
    }

    func testDeckBodyRespectsServerLimits() {
        let long = String(repeating: "x", count: 81)
        let many = (0..<500).map { "w\($0)" }
        let body = BackendAPI.DeckBody(
            showId: 1, season: 1, episode: 1, language: .russian, level: nil,
            wordCount: 500, knownTerms: [long] + many, subtitles: nil)
        XCTAssertEqual(body.wordCount, 40)
        XCTAssertEqual(body.knownTerms.count, DeckRequest.knownTermsLimit)
        XCTAssertFalse(body.knownTerms.contains(long))
    }

    func testDiscussBodyTrimsAndLimitsTurns() throws {
        let body = BackendAPI.DiscussBody(
            showId: 1, season: 1, episode: 2, language: .english, level: .c1,
            turns: [
                EpisodeDiscussion.Turn(speaker: .monchik, text: "Hi"),
                EpisodeDiscussion.Turn(speaker: .learner, text: "  "),
                EpisodeDiscussion.Turn(speaker: .learner, text: String(repeating: "a", count: 700)),
            ],
            retelling: "")
        XCTAssertEqual(body.turns.map(\.speaker), ["monchik", "learner"])
        XCTAssertEqual(body.turns[1].text.count, 600)
        XCTAssertNil(body.retelling)
        XCTAssertEqual(try json(body)["language"] as? String, "en")
    }

    // MARK: - Ответы

    func testPlanStatusDecodes() throws {
        let plan = try JSONDecoder().decode(BackendAPI.PlanStatus.self, from: Data("""
        {"plan":"promo","active":true,"unitsTotal":2000000,"unitsLeft":1000000,
         "periodEnd":"2026-10-28T12:00:00.000Z"}
        """.utf8))
        XCTAssertEqual(plan.kind, .promo)
        XCTAssertEqual(plan.fractionLeft, 0.5)
        XCTAssertEqual(plan.approximateDecksLeft, 1_000_000 / BackendAPI.unitsPerDeck)
        XCTAssertNotNil(plan.periodEndDate)
    }

    func testEmptyPlanIsSafe() {
        let plan = BackendAPI.PlanStatus(plan: "none", active: false, unitsTotal: 0, unitsLeft: 0,
                                         periodEnd: nil)
        XCTAssertEqual(plan.kind, .none)
        XCTAssertEqual(plan.fractionLeft, 0, "без деления на ноль")
        XCTAssertNil(plan.periodEndDate)
    }

    func testDeckResponseCarriesAnImportableDeck() throws {
        let response = try JSONDecoder().decode(BackendAPI.DeckResponse.self, from: Data("""
        {"deck":{"format":"ajfm-deck","version":1,
                 "deck":{"name":"S01E03 · The Thumb","folder":"Сериалы/Friends/Сезон 1",
                         "source":"Friends S01E03"},
                 "notes":[{"term":"hang out","translation":"тусоваться"}]},
         "source":"model",
         "plan":{"plan":"promo","active":true,"unitsTotal":10,"unitsLeft":5,"periodEnd":null}}
        """.utf8))
        XCTAssertEqual(response.deck.deck.folder, "Сериалы/Friends/Сезон 1")
        XCTAssertEqual(response.deck.notes.first?.term, "hang out")
        let plan = ImportPlanner.plan(file: response.deck, existingTerms: [:])
        XCTAssertEqual(plan.folderPath, ["Сериалы", "Friends", "Сезон 1"])
    }

    func testDiscussResponseWithAndWithoutTip() throws {
        let withTip = try JSONDecoder().decode(BackendAPI.DiscussResponse.self, from: Data("""
        {"reply":"Why?","tip":{"said":"a","better":"b","why":"c"},"finished":false,
         "plan":{"plan":"subscription","active":true,"unitsTotal":1,"unitsLeft":1,"periodEnd":null}}
        """.utf8))
        XCTAssertEqual(withTip.asReply.tip?.better, "b")
        let without = try JSONDecoder().decode(BackendAPI.DiscussResponse.self, from: Data("""
        {"reply":"Bye!","tip":null,"finished":true,
         "plan":{"plan":"subscription","active":true,"unitsTotal":1,"unitsLeft":1,"periodEnd":null}}
        """.utf8))
        XCTAssertNil(without.asReply.tip)
        XCTAssertTrue(without.asReply.finished)
    }

    // MARK: - Ошибки

    func testErrorCodeFromBodyOrStatus() {
        let failure = BackendAPI.Failure.from(status: 402, body: Data(#"{"error":"no_plan"}"#.utf8))
        XCTAssertEqual(failure.code, "no_plan")
        XCTAssertTrue(failure.needsPlan)
        let bare = BackendAPI.Failure.from(status: 500, body: Data("oops".utf8))
        XCTAssertEqual(bare.code, "http_500")
        XCTAssertFalse(bare.needsPlan)
    }

    func testEveryKnownCodeHasItsOwnMessage() {
        let codes = ["no_plan", "plan_expired", "quota_exceeded", "episode_locked",
                     "episode_not_found", "rate_limited", "invalid_code", "code_not_valid",
                     "subscription_not_active", "conversation_over", "model_busy", "model_error",
                     "unauthorized"]
        let fallback = BackendAPI.Failure.message(for: "something_new")
        for code in codes {
            let message = BackendAPI.Failure.message(for: code)
            XCTAssertFalse(message.isEmpty, code)
            XCTAssertNotEqual(message, fallback, code)
        }
        XCTAssertTrue(fallback.contains("something_new"))
    }

    func testMessagesAreTranslated() {
        Loc.language = .portuguese
        XCTAssertTrue(BackendAPI.Failure.message(for: "no_plan").contains("Recap Plus"))
        XCTAssertFalse(BackendAPI.Failure.message(for: "no_plan").contains("Это"))
    }
}
