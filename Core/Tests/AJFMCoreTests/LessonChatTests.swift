import XCTest
@testable import AJFMCore

/// Инструкция разговора об уроке совпадает с серверной (schema/prompts/lesson-chat.json).
final class LessonChatTests: XCTestCase {

    private struct Entry: Decodable {
        struct Input: Decodable {
            let title: String
            let terms: [String]
            let language: String
            let target: String
            let level: String?
            let retelling: String?
        }
        let input: Input
        let system: String
    }

    private func entries() throws -> [Entry] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "schema/prompts/lesson-chat.json"))
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    func testSystemMatchesTheServer() throws {
        let all = try entries()
        XCTAssertFalse(all.isEmpty)
        for entry in all {
            let input = entry.input
            let system = LessonChat.system(
                language: try XCTUnwrap(AppLanguage(rawValue: input.language)),
                level: try input.level.map { try XCTUnwrap(CEFRLevel(rawValue: $0)) },
                target: try XCTUnwrap(StudyLanguage(rawValue: input.target)),
                title: input.title, terms: input.terms, retelling: input.retelling)
            XCTAssertEqual(system, entry.system, "\(input.target) → \(input.language)")
        }
    }

    func testTermsAreDeduplicatedAndLimited() {
        XCTAssertEqual(LessonChat.cleanTerms(["casa", " Casa ", "", "pão"]), ["casa", "pão"])
        XCTAssertEqual(LessonChat.cleanTerms((0..<60).map { "w\($0)" }).count, LessonChat.termsLimit)
    }

    func testBlankRetellingAddsNothing() {
        let system = LessonChat.system(language: .russian, level: nil, target: .italian,
                                       title: "Lezione", terms: ["casa"], retelling: "  ")
        XCTAssertFalse(system.contains("<retelling>\n"))
    }
}

final class LessonChatBodyTests: XCTestCase {
    func testBodyCarriesTheLessonAndLimits() throws {
        let body = BackendAPI.LessonChatBody(
            title: "  Aula 5 ", terms: ["comer", "Comer", " ", "beber"], language: .russian,
            level: .a2, turns: [EpisodeDiscussion.Turn(speaker: .monchik, text: "Olá! ", signature: "ab12"),
                                EpisodeDiscussion.Turn(speaker: .learner, text: "  ")],
            retelling: "  ", target: .portuguese)
        XCTAssertEqual(body.title, "Aula 5")
        XCTAssertEqual(body.terms, ["comer", "beber"])
        XCTAssertEqual(body.target, "pt-PT")
        XCTAssertEqual(body.turns.map(\.text), ["Olá! "], "реплика Мончика — ровно как была")
        XCTAssertEqual(body.turns.first?.sig, "ab12")
        XCTAssertNil(body.retelling)
        XCTAssertNil(body.questions)
    }

    func testEnglishLessonSendsNoTarget() {
        let body = BackendAPI.LessonChatBody(title: "Travel", terms: ["get by"], language: .russian,
                                             level: nil, turns: [], retelling: nil, questions: 99)
        XCTAssertNil(body.target)
        XCTAssertEqual(body.questions, EpisodeDiscussion.maxLearnerTurns)
    }
}
