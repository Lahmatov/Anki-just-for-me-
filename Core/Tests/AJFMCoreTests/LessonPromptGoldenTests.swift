import XCTest
@testable import AJFMCore

/// Промпт урока живёт в двух местах — здесь и на сервере (backend/src/prompts.ts).
/// Обе копии сверяются с одним эталоном schema/prompts/lesson.json, который
/// пишет серверный тест: правка одной копии без другой валит тесты.
final class LessonPromptGoldenTests: XCTestCase {

    private struct Entry: Decodable {
        struct Input: Decodable {
            let target: String
            let language: String
            let level: String?
            let wordCount: Int
            let title: String?
            let knownTerms: [String]
            let lesson: String
        }
        let input: Input
        let system: String
        let user: String
    }

    /// Core/Tests/AJFMCoreTests/этот файл → корень репозитория.
    private func entries() throws -> [Entry] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "schema/prompts/lesson.json"))
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    private func request(_ input: Entry.Input) throws -> DeckRequest {
        DeckRequest(
            topic: input.title ?? "", wordCount: input.wordCount,
            level: try input.level.map { try XCTUnwrap(CEFRLevel(rawValue: $0)) },
            language: try XCTUnwrap(AppLanguage(rawValue: input.language)),
            knownTerms: input.knownTerms,
            target: try XCTUnwrap(StudyLanguage(rawValue: input.target)),
            lesson: input.lesson)
    }

    func testThereAreCasesForEveryStudyLanguage() throws {
        let targets = Set(try entries().map(\.input.target))
        XCTAssertEqual(targets, Set(StudyLanguage.allCases.map(\.rawValue)))
    }

    func testSystemPromptMatchesTheServer() throws {
        for entry in try entries() {
            XCTAssertEqual(try request(entry.input).system, entry.system,
                           "\(entry.input.target) → \(entry.input.language)")
        }
    }

    func testUserMessageMatchesTheServer() throws {
        for entry in try entries() {
            XCTAssertEqual(try request(entry.input).userMessage, entry.user,
                           "\(entry.input.target) → \(entry.input.language)")
        }
    }
}
