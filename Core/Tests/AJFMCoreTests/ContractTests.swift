import XCTest
@testable import AJFMCore

/// Контракт API с сервером (P-71), общий с backend/test/contract.test.ts.
///
/// Запросы: приложение кодирует их ровно как в schema/api/requests — эти же
/// файлы сервер проверяет на приём. Ответы: файлы schema/api/responses пишет
/// серверный тест из настоящих ответов, а здесь — что приложение их читает.
/// Сломается одна сторона — упадут тесты, а не приложения у людей.
final class ContractTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "schema/api", directoryHint: .isDirectory)
    }

    private func fixture(_ name: String) throws -> (route: String, body: NSDictionary) {
        let data = try Data(contentsOf: root.appending(path: "requests/\(name).json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (try XCTUnwrap(object["route"] as? String),
                try XCTUnwrap(object["body"] as? [String: Any]) as NSDictionary)
    }

    private func encoded(_ value: some Encodable) throws -> NSDictionary {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any]) as NSDictionary
    }

    private func response(_ name: String) throws -> Data {
        try Data(contentsOf: root.appending(path: "responses/\(name).json"))
    }

    // MARK: - Запросы

    func testDeckRequestMatchesTheContract() throws {
        let body = BackendAPI.DeckBody(
            showId: 431, season: 1, episode: 3, language: .russian, level: .b1, wordCount: 20,
            knownTerms: ["hello"], subtitles: nil, requestId: "contract-deck-1", target: .portuguese)
        let contract = try fixture("deck")
        XCTAssertEqual(contract.route, "POST /v1/deck")
        XCTAssertEqual(try encoded(body), contract.body)
    }

    func testLessonRequestMatchesTheContract() throws {
        let request = DeckRequest(topic: "Aula 5", wordCount: 20, level: .a2, language: .russian,
                                  knownTerms: ["olá"], target: .portuguese,
                                  lesson: "Aula 5 — pretérito perfeito\ncomer → comi")
        let contract = try fixture("lesson")
        XCTAssertEqual(contract.route, "POST /v1/lesson")
        XCTAssertEqual(try encoded(BackendAPI.LessonBody(request, requestId: "contract-lesson-1")), contract.body)
    }

    func testDiscussRequestMatchesTheContract() throws {
        let body = BackendAPI.DiscussBody(
            showId: 431, season: 1, episode: 3, language: .russian, level: .b1, turns: [],
            retelling: "Phoebe finds a thumb.", questions: 3, target: .portuguese)
        let contract = try fixture("discuss")
        XCTAssertEqual(contract.route, "POST /v1/discuss")
        XCTAssertEqual(try encoded(body), contract.body)
    }

    func testLessonChatRequestMatchesTheContract() throws {
        let body = BackendAPI.LessonChatBody(
            title: "Aula 5", terms: ["comer", "apetecer"], language: .russian, level: .a2, turns: [],
            retelling: "Ontem comi bacalhau.", target: .portuguese)
        let contract = try fixture("lesson-chat")
        XCTAssertEqual(contract.route, "POST /v1/lesson/chat")
        XCTAssertEqual(try encoded(body), contract.body)
    }

    func testSupportRequestMatchesTheContract() throws {
        let diagnostics = SupportDiagnostics.make(appVersion: "0.4 (17)", systemVersion: "26.1",
                                                  device: "iPad", language: .russian,
                                                  studyLanguage: .portuguese)
        let body = BackendAPI.SupportTicketBody(category: .bug, message: "Диктант не читает фразу вслух.",
                                                contact: "anna@example.com", diagnostics: diagnostics)
        let contract = try fixture("support")
        XCTAssertEqual(contract.route, "POST /v1/support")
        XCTAssertEqual(try encoded(body), contract.body)
    }

    // MARK: - Ответы

    func testSupportResponsesDecode() throws {
        let created = try JSONDecoder().decode(BackendAPI.SupportTicketResponse.self, from: response("support"))
        XCTAssertTrue(created.ticket.id.hasPrefix("R-"))
        XCTAssertEqual(created.ticket.kind, .bug)
        let list = try JSONDecoder().decode(BackendAPI.SupportTicketList.self, from: response("support-list"))
        XCTAssertEqual(list.tickets.count, 1)
        XCTAssertFalse(list.tickets[0].isAnswered)
    }

    func testDeckAndLessonResponsesDecode() throws {
        for name in ["deck", "lesson"] {
            let decoded = try JSONDecoder().decode(BackendAPI.DeckResponse.self, from: response(name))
            XCTAssertFalse(decoded.deck.notes.isEmpty, name)
            XCTAssertTrue(decoded.plan.active, name)
        }
    }

    func testChatResponsesDecodeWithTheirSignature() throws {
        for name in ["discuss", "lesson-chat"] {
            let decoded = try JSONDecoder().decode(BackendAPI.DiscussResponse.self, from: response(name))
            XCTAssertFalse(decoded.reply.isEmpty, name)
            XCTAssertNotNil(decoded.asReply.signature, "\(name): без подписи следующая реплика не пройдёт")
        }
    }

    func testPlanResponsesDecode() throws {
        for name in ["me", "redeem"] {
            let plan = try JSONDecoder().decode(BackendAPI.PlanStatus.self, from: response(name))
            XCTAssertEqual(plan.kind, .promo, name)
            XCTAssertNotNil(plan.periodEndDate, "\(name): дата конца доступа не разобралась")
        }
    }

    func testBackupListDecodes() throws {
        let list = try JSONDecoder().decode(CloudBackupList.self, from: response("backups"))
        XCTAssertEqual(list.backups.count, 1)
        XCTAssertEqual(list.backups.first?.bytes, 4)
        XCTAssertGreaterThan(list.keep, 0)
    }
}

final class ClientHeaderTests: XCTestCase {
    /// Тот же вид, что разбирает сервер (compat.ts, clientBuild).
    func testHeaderCarriesVersionAndBuild() {
        XCTAssertEqual(BackendAPI.clientHeader(version: "0.4", build: "17"), "ios/0.4 (17)")
    }

    func testMissingOrBrokenValuesStillGiveAParsableHeader() {
        XCTAssertEqual(BackendAPI.clientHeader(version: nil, build: nil), "ios/0 (0)")
        XCTAssertEqual(BackendAPI.clientHeader(version: " ", build: "abc"), "ios/0 (0)")
    }
}
