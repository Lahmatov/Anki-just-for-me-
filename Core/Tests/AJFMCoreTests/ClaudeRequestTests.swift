import XCTest
@testable import AJFMCore

/// Тело запроса под каждую модель. Лишний параметр — это ошибка 400,
/// то есть неработающая кнопка, которую не отловить без сети.
final class ClaudeRequestTests: XCTestCase {

    private func body(
        _ model: ModelPricing, schema: String? = nil, effort: ClaudeRequest.Effort = .medium
    ) throws -> [String: Any] {
        try ClaudeRequest(
            model: model, system: "sys", userMessage: "hi", maxTokens: 1_000,
            effort: effort, outputSchemaJSON: schema
        ).body()
    }

    func testBasicFields() throws {
        let body = try body(ClaudeModel.sonnet5)
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 1_000)
        XCTAssertEqual(body["system"] as? String, "sys")
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
        XCTAssertEqual(messages?.first?["content"] as? String, "hi")
    }

    func testThinkingAndEffortOnlyWhereSupported() throws {
        let sonnet = try body(ClaudeModel.sonnet5, effort: .low)
        XCTAssertEqual((sonnet["thinking"] as? [String: Any])?["type"] as? String, "adaptive")
        XCTAssertEqual((sonnet["output_config"] as? [String: Any])?["effort"] as? String, "low")

        // Haiku отвергает и то и другое — запрос обязан быть без них.
        let haiku = try body(ClaudeModel.haiku45)
        XCTAssertNil(haiku["thinking"])
        XCTAssertNil(haiku["output_config"])
    }

    func testSchemaGoesIntoOutputConfigForEveryModel() throws {
        let schema = #"{ "type": "object", "additionalProperties": false, "properties": {} }"#
        for model in ClaudeModel.all {
            let config = try body(model, schema: schema)["output_config"] as? [String: Any]
            let format = config?["format"] as? [String: Any]
            XCTAssertEqual(format?["type"] as? String, "json_schema", model.id)
            XCTAssertEqual((format?["schema"] as? [String: Any])?["type"] as? String, "object")
        }
    }

    func testSchemaAndEffortLiveTogether() throws {
        let config = try body(ClaudeModel.opus5, schema: #"{"type":"object"}"#)["output_config"]
            as? [String: Any]
        XCTAssertNotNil(config?["effort"])
        XCTAssertNotNil(config?["format"])
    }

    func testBrokenSchemaThrowsInsteadOfSendingGarbage() {
        XCTAssertThrowsError(try body(ClaudeModel.opus5, schema: "{ not json"))
    }

    func testServerFallbackOnlyForOpus() throws {
        let opus = ClaudeRequest(model: ClaudeModel.opus5, system: "", userMessage: "",
                                 maxTokens: 10)
        XCTAssertEqual(try opus.body()["fallbacks"] as? String, "default")
        XCTAssertEqual(opus.betaHeader, ClaudeRequest.fallbackBeta)

        for model in [ClaudeModel.sonnet5, ClaudeModel.haiku45] {
            let request = ClaudeRequest(model: model, system: "", userMessage: "", maxTokens: 10)
            XCTAssertNil(try request.body()["fallbacks"], model.id)
            XCTAssertNil(request.betaHeader, model.id)
        }
    }

    func testBodyIsSerializable() throws {
        let data = try JSONSerialization.data(withJSONObject: try body(
            ClaudeModel.opus5, schema: DeckRequest.outputSchemaJSON))
        XCTAssertFalse(data.isEmpty)
    }

    func testStopReasons() {
        XCTAssertEqual(ClaudeStopReason(raw: "end_turn"), .finished)
        XCTAssertEqual(ClaudeStopReason(raw: nil), .finished)
        XCTAssertEqual(ClaudeStopReason(raw: "max_tokens"), .truncated)
        XCTAssertEqual(ClaudeStopReason(raw: "refusal"), .refused)
        XCTAssertEqual(ClaudeStopReason(raw: "pause_turn"), .other("pause_turn"))
    }
}
