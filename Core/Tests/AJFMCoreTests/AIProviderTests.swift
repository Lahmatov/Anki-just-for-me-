import XCTest
@testable import AJFMCore

final class AIProviderTests: XCTestCase {

    func testEveryProviderUsesHTTPS() {
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.endpoint.scheme, "https", provider.rawValue)
            XCTAssertEqual(provider.consoleURL.scheme, "https", provider.rawValue)
        }
    }

    func testOpenAICompatibleProvidersHitChatCompletions() {
        for provider in AIProvider.allCases where provider != .anthropic {
            XCTAssertTrue(provider.endpoint.path.hasSuffix("/chat/completions"), provider.rawValue)
        }
    }

    func testEveryProviderHasADefaultModel() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.defaultModel.isEmpty, provider.rawValue)
        }
    }

    func testKeychainAccountsAreUnique() {
        let accounts = AIProvider.allCases.map(\.keychainAccount)
        XCTAssertEqual(Set(accounts).count, accounts.count)
    }

    func testClaudeKeepsItsOldKeychainAccount() {
        // Иначе после обновления вписанный ключ Claude «пропал» бы.
        XCTAssertEqual(AIProvider.anthropic.keychainAccount, "claude-api-key")
    }

    func testOnlyClaudeTracksCost() {
        XCTAssertEqual(AIProvider.allCases.filter(\.tracksCost), [.anthropic])
    }

    func testOpenAIUsesMaxCompletionTokens() {
        XCTAssertEqual(AIProvider.openai.maxTokensKey, "max_completion_tokens")
        XCTAssertEqual(AIProvider.deepseek.maxTokensKey, "max_tokens")
    }
}

final class ChatCompletionsTests: XCTestCase {

    private let schema = #"{"type":"object","properties":{"reply":{"type":"string"}},"required":["reply"]}"#

    private func request(schema: String? = nil) -> ClaudeRequest {
        ClaudeRequest(model: ClaudeModel.haiku45, system: "You are Monchik.",
                      conversation: [.init(.user, "Hi"), .init(.assistant, "Hello!"), .init(.user, "Bye")],
                      maxTokens: 400, outputSchemaJSON: schema)
    }

    func testSystemGoesFirstAndConversationFollows() throws {
        let body = try ChatCompletions.body(for: request(), provider: .deepseek, model: "deepseek-chat")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages.first?["content"], "You are Monchik.")
        XCTAssertEqual(body["model"] as? String, "deepseek-chat")
        XCTAssertEqual(body["max_tokens"] as? Int, 400)
    }

    func testNoSchemaMeansNoResponseFormat() throws {
        let body = try ChatCompletions.body(for: request(), provider: .openai, model: "m")
        XCTAssertNil(body["response_format"])
    }

    func testSchemaProvidersGetJSONSchemaFormat() throws {
        let body = try ChatCompletions.body(for: request(schema: schema), provider: .gemini, model: "m")
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let inner = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertNotNil(inner["schema"] as? [String: Any])
    }

    func testJSONObjectProvidersGetSchemaAsText() throws {
        let body = try ChatCompletions.body(for: request(schema: schema), provider: .kimi, model: "m")
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_object")
        let system = try XCTUnwrap((body["messages"] as? [[String: String]])?.first?["content"])
        XCTAssertTrue(system.contains("JSON"), "json_object требует слова JSON в инструкции")
        XCTAssertTrue(system.contains(#""reply""#))
    }

    func testOpenAIBodyUsesMaxCompletionTokens() throws {
        let body = try ChatCompletions.body(for: request(), provider: .openai, model: "gpt-5-mini")
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 400)
        XCTAssertNil(body["max_tokens"])
    }

    func testBrokenSchemaThrows() {
        XCTAssertThrowsError(try ChatCompletions.body(for: request(schema: "{not json"),
                                                      provider: .openai, model: "m"))
    }

    // MARK: - Ответ

    func testParsesTextUsageAndStop() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"{\"reply\":\"Hi\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":120,"completion_tokens":30}}"#
        let response = try ChatCompletions.parse(Data(json.utf8))
        XCTAssertEqual(response.text, #"{"reply":"Hi"}"#)
        XCTAssertEqual(response.inputTokens, 120)
        XCTAssertEqual(response.outputTokens, 30)
        XCTAssertEqual(response.stopReason, .finished)
    }

    func testLengthMeansTruncated() throws {
        let json = #"{"choices":[{"message":{"content":"{\"re"},"finish_reason":"length"}]}"#
        XCTAssertEqual(try ChatCompletions.parse(Data(json.utf8)).stopReason, .truncated)
    }

    func testContentFilterAndRefusalMeanRefused() throws {
        let filtered = #"{"choices":[{"message":{"content":""},"finish_reason":"content_filter"}]}"#
        XCTAssertEqual(try ChatCompletions.parse(Data(filtered.utf8)).stopReason, .refused)
        let refusal = #"{"choices":[{"message":{"content":null,"refusal":"I can't"},"finish_reason":"stop"}]}"#
        XCTAssertEqual(try ChatCompletions.parse(Data(refusal.utf8)).stopReason, .refused)
    }

    func testEmptyContentIsNil() throws {
        let json = #"{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}"#
        XCTAssertNil(try ChatCompletions.parse(Data(json.utf8)).text)
    }

    func testMissingUsageIsZero() throws {
        let json = #"{"choices":[{"message":{"content":"ok"}}]}"#
        let response = try ChatCompletions.parse(Data(json.utf8))
        XCTAssertEqual(response.inputTokens, 0)
        XCTAssertEqual(response.stopReason, .finished)
    }

    func testNotJSONThrows() {
        XCTAssertThrowsError(try ChatCompletions.parse(Data("<html>".utf8)))
    }

    func testErrorMessageFromObjectAndGeminiArray() {
        XCTAssertEqual(ChatCompletions.errorMessage(from: Data(#"{"error":{"message":"bad key"}}"#.utf8)),
                       "bad key")
        XCTAssertEqual(ChatCompletions.errorMessage(from: Data(#"[{"error":{"message":"quota"}}]"#.utf8)),
                       "quota")
        XCTAssertNil(ChatCompletions.errorMessage(from: Data("oops".utf8)))
    }
}
