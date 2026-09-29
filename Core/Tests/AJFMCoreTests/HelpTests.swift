import XCTest
@testable import AJFMCore

final class HelpCenterTests: XCTestCase {

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    func testEntriesHaveUniqueIDs() {
        let ids = HelpCenter.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryEntryIsTranslated() {
        for language in AppLanguage.allCases {
            Loc.language = language
            for entry in HelpCenter.entries {
                XCTAssertFalse(entry.question.isEmpty, "\(language) \(entry.id)")
                XCTAssertFalse(entry.answer.isEmpty, "\(language) \(entry.id)")
            }
        }
    }

    func testEmptyQueryShowsEverything() {
        XCTAssertEqual(HelpCenter.search("  ").count, HelpCenter.entries.count)
    }

    func testFindsByQuestionWords() {
        Loc.language = .russian
        XCTAssertEqual(HelpCenter.search("отменить подписку").first?.id, "plus")
    }

    func testIgnoresCaseAndDiacritics() {
        Loc.language = .portuguese
        XCTAssertEqual(HelpCenter.search("ANIMACOES").first?.id, "motion")
    }

    func testRussianYoIsTheSameAsYe() {
        Loc.language = .russian
        XCTAssertFalse(HelpCenter.search("распознаётся").isEmpty)
        XCTAssertFalse(HelpCenter.search("распознается").isEmpty)
    }

    func testQuestionMatchRanksAboveAnswerMatch() {
        let entries = [
            HelpCenter.Entry(id: "a", question: "Other", answer: "About keys and more"),
            HelpCenter.Entry(id: "b", question: "Where are my keys?", answer: "Here"),
        ]
        XCTAssertEqual(HelpCenter.search("keys", in: entries).map(\.id), ["b", "a"])
    }

    func testNothingFoundIsEmpty() {
        XCTAssertTrue(HelpCenter.search("zzzqqq").isEmpty)
    }

    func testOneLetterWordsAreIgnored() {
        XCTAssertEqual(HelpCenter.search("a").count, HelpCenter.entries.count)
    }
}

final class HelpChatTests: XCTestCase {

    override func tearDown() {
        Loc.language = .russian
        super.tearDown()
    }

    func testSystemPromptContainsFactsInEnglishAndTargetLanguage() {
        Loc.language = .russian
        let system = HelpChat.system(language: .portuguese)
        XCTAssertTrue(system.contains("Profile → AI keys"), "факты — по-английски")
        XCTAssertTrue(system.contains(AppLanguage.portuguese.promptName))
        XCTAssertEqual(Loc.language, .russian, "язык интерфейса не должен меняться")
    }

    func testParsesOnTopicReply() throws {
        let reply = try HelpChat.parseReply(#"{"answer":"Go to Shows.","onTopic":true,"suggestEmail":false}"#)
        XCTAssertEqual(reply, HelpChat.Reply(answer: "Go to Shows.", onTopic: true, suggestEmail: false))
    }

    func testOffTopicReplaceTheModelsAnswer() throws {
        Loc.language = .english
        let reply = try HelpChat.parseReply(#"{"answer":"Here is your essay…","onTopic":false,"suggestEmail":true}"#)
        XCTAssertEqual(reply.answer, HelpChat.offTopicReply)
        XCTAssertFalse(reply.suggestEmail, "письмо не предлагаем на вопрос не по теме")
    }

    func testLongAnswerIsClipped() throws {
        let long = String(repeating: "a", count: 2_000)
        let reply = try HelpChat.parseReply(#"{"answer":"\#(long)","onTopic":true,"suggestEmail":false}"#)
        XCTAssertEqual(reply.answer.count, HelpChat.answerLimit)
    }

    func testMissingFlagsDefaultToOnTopicWithoutEmail() throws {
        let reply = try HelpChat.parseReply(#"{"answer":"Yes"}"#)
        XCTAssertTrue(reply.onTopic)
        XCTAssertFalse(reply.suggestEmail)
    }

    func testBrokenOrEmptyReplyThrows() {
        XCTAssertThrowsError(try HelpChat.parseReply("not json"))
        XCTAssertThrowsError(try HelpChat.parseReply(#"{"answer":"  "}"#))
    }

    func testQuestionIsTrimmedAndLimited() {
        XCTAssertNil(HelpChat.cleanQuestion("  "))
        XCTAssertNil(HelpChat.cleanQuestion("a"))
        XCTAssertEqual(HelpChat.cleanQuestion("  Hi there "), "Hi there")
        XCTAssertEqual(HelpChat.cleanQuestion(String(repeating: "x", count: 900))?.count,
                       HelpChat.questionLimit)
    }

    func testHistoryKeepsOnlyTheTail() {
        let history = (0..<100).map { HelpChat.Message(author: .user, text: "\($0)") }
        let trimmed = HelpChat.trimmed(history)
        XCTAssertEqual(trimmed.count, HelpChat.historyLimit)
        XCTAssertEqual(trimmed.last?.text, "99")
    }

    func testMessagesRoundTripThroughJSON() throws {
        let message = HelpChat.Message(author: .monchik, text: "Привет", suggestEmail: true)
        let decoded = try JSONDecoder().decode([HelpChat.Message].self,
                                               from: JSONEncoder().encode([message]))
        XCTAssertEqual(decoded, [message])
    }
}
