import XCTest
@testable import AJFMCore

final class EpisodeDiscussionTests: XCTestCase {

    private typealias D = EpisodeDiscussion

    private func turns(learnerAnswers: Int) -> [D.Turn] {
        var result = [D.Turn(speaker: .monchik, text: "Hi! What happened?")]
        for index in 0..<learnerAnswers {
            result.append(D.Turn(speaker: .learner, text: "Answer \(index)"))
            if index < learnerAnswers - 1 {
                result.append(D.Turn(speaker: .monchik, text: "Question \(index)"))
            }
        }
        return result
    }

    // MARK: - Инструкция

    func testSystemUsesTheReferenceAndForbidsMemory() {
        let system = D.system(language: .russian, level: .b1, episodeTitle: "Friends S01E02",
                              reference: .synopsis("Ross finds out."), retelling: nil)
        XCTAssertTrue(system.contains("<synopsis>\nRoss finds out.\n</synopsis>"))
        XCTAssertTrue(system.contains("Do not rely on your memory"))
        XCTAssertTrue(system.contains("Never reveal events of later episodes"))
        XCTAssertTrue(system.contains("about B1"))
        XCTAssertTrue(system.contains("in Russian"))
    }

    func testWithoutReferenceMonchikAsksOpinionsNotFacts() {
        let system = D.system(language: .english, level: nil, episodeTitle: "X",
                              reference: nil, retelling: nil)
        XCTAssertTrue(system.contains("There is no reference"))
        XCTAssertTrue(system.contains("intermediate"))
    }

    func testLongReferenceIsCut() {
        let long = String(repeating: "a", count: D.referenceLimit + 500)
        let system = D.system(language: .russian, level: nil, episodeTitle: "X",
                              reference: .subtitles(long), retelling: nil)
        XCTAssertFalse(system.contains(String(repeating: "a", count: D.referenceLimit + 1)))
        XCTAssertTrue(system.contains("<subtitles>"))
    }

    func testRetellingIsIncludedOnlyWhenPresent() {
        let with = D.system(language: .russian, level: nil, episodeTitle: "X",
                            reference: nil, retelling: "Ross was sad.")
        XCTAssertTrue(with.contains("<retelling>\nRoss was sad.\n</retelling>"))
        let blank = D.system(language: .russian, level: nil, episodeTitle: "X",
                             reference: nil, retelling: "  ")
        XCTAssertFalse(blank.contains("<retelling>"))
    }

    // MARK: - История

    func testConversationStartsWithAUserKickoff() {
        let messages = D.messages(for: [])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .user)
    }

    func testRolesAlternate() {
        let messages = D.messages(for: turns(learnerAnswers: 2))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant, .user])
    }

    func testSameSpeakerTwiceIsMergedAndBlankSkipped() {
        let messages = D.messages(for: [
            D.Turn(speaker: .monchik, text: "Hi!"),
            D.Turn(speaker: .learner, text: "Ross"),
            D.Turn(speaker: .learner, text: "  "),
            D.Turn(speaker: .learner, text: "was sad"),
        ])
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(messages.last?.text, "Ross\nwas sad")
    }

    func testLastAnswerAsksForAGoodbye() {
        let last = D.messages(for: turns(learnerAnswers: D.maxLearnerTurns)).last
        XCTAssertTrue(last?.text.contains("say goodbye") ?? false)
        let earlier = D.messages(for: turns(learnerAnswers: D.maxLearnerTurns - 1)).last
        XCTAssertFalse(earlier?.text.contains("say goodbye") ?? true)
    }

    func testTurnCounting() {
        XCTAssertEqual(D.learnerTurnCount(turns(learnerAnswers: 3)), 3)
        XCTAssertFalse(D.isLastTurn(turns(learnerAnswers: D.maxLearnerTurns - 1)))
        XCTAssertTrue(D.isLastTurn(turns(learnerAnswers: D.maxLearnerTurns)))
    }

    // MARK: - Ответ

    func testReplyWithTip() throws {
        let reply = try D.parseReply("""
        {"reply": "Nice! Why was he upset?",
         "tip": {"said": "he don't know", "better": "he doesn't know", "why": "третье лицо"},
         "finished": false}
        """)
        XCTAssertEqual(reply.text, "Nice! Why was he upset?")
        XCTAssertEqual(reply.tip?.better, "he doesn't know")
        XCTAssertFalse(reply.finished)
    }

    func testEmptyOrFakeTipBecomesNil() throws {
        let empty = try D.parseReply(#"{"reply": "Hi", "tip": {"said": "", "better": "", "why": ""}, "finished": false}"#)
        XCTAssertNil(empty.tip)
        let same = try D.parseReply(#"{"reply": "Hi", "tip": {"said": "Okay", "better": "okay", "why": "x"}, "finished": false}"#)
        XCTAssertNil(same.tip, "поправка, совпадающая со сказанным, — не поправка")
        let missing = try D.parseReply(#"{"reply": "Bye!", "finished": true}"#)
        XCTAssertNil(missing.tip)
        XCTAssertTrue(missing.finished)
    }

    func testBrokenReplyIsAnError() {
        XCTAssertThrowsError(try D.parseReply("not json")) {
            XCTAssertEqual($0 as? D.ReplyError, .unreadable)
        }
        XCTAssertThrowsError(try D.parseReply(#"{"reply": "  "}"#))
    }

    func testSchemaIsStrictAndComplete() throws {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(D.outputSchemaJSON.utf8)) as? [String: Any])
        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
        let required = Set(try XCTUnwrap(object["required"] as? [String]))
        let properties = Set(try XCTUnwrap(object["properties"] as? [String: Any]).keys)
        XCTAssertEqual(required, properties)
    }

    // MARK: - Карточки

    func testTipsBecomeADeckWithoutRepeats() throws {
        let tip = D.Tip(said: "he don't know", better: "he doesn't know", why: "третье лицо")
        let turns = [
            D.Turn(speaker: .monchik, text: "Hi"),
            D.Turn(speaker: .learner, text: "he don't know"),
            D.Turn(speaker: .monchik, text: "Right!", tip: tip),
            D.Turn(speaker: .monchik, text: "Again", tip: tip),
        ]
        let file = try XCTUnwrap(D.deckFile(from: turns, name: "Friends S01E01", folder: "X"))
        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes[0].term, "he doesn't know")
        XCTAssertEqual(file.notes[0].translation, "третье лицо")
        XCTAssertEqual(file.notes[0].note, "✗ he don't know")
    }

    func testNoTipsNoDeck() {
        XCTAssertNil(D.deckFile(from: [D.Turn(speaker: .monchik, text: "Hi")], name: "X", folder: nil))
    }
}
