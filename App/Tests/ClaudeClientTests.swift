import XCTest
import AJFMCore
@testable import AJFM

/// Разбор ответа модели. Сетевой вызов здесь не проверяется — проверяется то,
/// что происходит с ответом, потому что ошибка на этом шаге стоит денег:
/// запрос уже оплачен, а результат потерян.
final class ClaudeClientTests: XCTestCase {

    private func response(_ blocks: [[String: Any]], input: Int = 13_000, output: Int = 1_500)
        -> [String: Any] {
        ["content": blocks, "usage": ["input_tokens": input, "output_tokens": output]]
    }

    // MARK: - Извлечение текста

    func testTakesTextBlock() {
        let json = response([["type": "text", "text": "{\"a\":1}"]])
        XCTAssertEqual(ClaudeClient.extractText(from: json), "{\"a\":1}")
    }

    func testSkipsThinkingBlocks() {
        // При включённом рассуждении ответ содержит и блоки размышлений —
        // в JSON должен попасть только текст.
        let json = response([
            ["type": "thinking", "thinking": "рассуждаю…"],
            ["type": "text", "text": "{\"a\":1}"],
        ])
        XCTAssertEqual(ClaudeClient.extractText(from: json), "{\"a\":1}")
    }

    func testJoinsSeveralTextBlocks() {
        let json = response([
            ["type": "text", "text": "{\"a\":"],
            ["type": "text", "text": "1}"],
        ])
        XCTAssertEqual(ClaudeClient.extractText(from: json), "{\"a\":1}")
    }

    func testEmptyContentGivesNil() {
        XCTAssertNil(ClaudeClient.extractText(from: response([])))
        XCTAssertNil(ClaudeClient.extractText(from: [:]))
        XCTAssertNil(ClaudeClient.extractText(from: response([["type": "thinking"]])))
    }

    // MARK: - Вырезание JSON

    func testPlainJSONPassesThrough() {
        XCTAssertEqual(ClaudeClient.extractJSONObject(from: "{\"a\":1}"), "{\"a\":1}")
    }

    func testStripsMarkdownFence() {
        // Модель просят не оборачивать ответ, но подстраховаться дешевле,
        // чем потерять оплаченный разбор.
        let fenced = "```json\n{\"a\":1}\n```"
        XCTAssertEqual(ClaudeClient.extractJSONObject(from: fenced), "{\"a\":1}")
    }

    func testStripsSurroundingProse() {
        let chatty = "Вот разбор:\n{\"a\":1}\nГотово."
        XCTAssertEqual(ClaudeClient.extractJSONObject(from: chatty), "{\"a\":1}")
    }

    func testKeepsNestedBraces() {
        let nested = "text {\"a\":{\"b\":2}} tail"
        XCTAssertEqual(ClaudeClient.extractJSONObject(from: nested), "{\"a\":{\"b\":2}}")
    }

    func testNoJSONGivesNil() {
        XCTAssertNil(ClaudeClient.extractJSONObject(from: "совсем не json"))
        XCTAssertNil(ClaudeClient.extractJSONObject(from: "}{"))
    }

    // MARK: - Разбор отчёта

    private let validReport = """
    {
      "understanding": {
        "correct": [{"claim": "Уолт отказался", "quote": "I don't want it."}],
        "incorrect": [], "missed": [], "coverage": 0.8
      },
      "language": {
        "grammar": [{"said": "he don't", "better": "he doesn't"}],
        "vocabulary": [], "fluencyNote": null,
        "suggestedWords": [{"term": "antagonist", "translation": "злодей"}]
      },
      "topPriorities": ["третье лицо"]
    }
    """

    func testDecodesValidReport() throws {
        let report = try ClaudeClient.decodeReport(from: validReport)
        XCTAssertEqual(report.understanding.coverage, 0.8)
        XCTAssertEqual(report.language.grammar.count, 1)
        XCTAssertEqual(report.topPriorities, ["третье лицо"])
    }

    func testDecodesReportWrappedInMarkdown() throws {
        let report = try ClaudeClient.decodeReport(from: "```json\n\(validReport)\n```")
        XCTAssertEqual(report.understanding.coverage, 0.8)
    }

    func testMissingJSONIsReported() {
        XCTAssertThrowsError(try ClaudeClient.decodeReport(from: "модель заболтала ответ"))
    }

    func testPartialReportSurvivesInsteadOfLosingThePayment() throws {
        // Одно поле не того типа не должно стоить оплаченного разбора:
        // лучше показать то, что разобралось, чем потерять всё.
        let report = try ClaudeClient.decodeReport(from: """
        {"understanding": 5, "language": {"grammar": [{"said": "a", "better": "b"}]},
         "topPriorities": ["важное"]}
        """)
        XCTAssertEqual(report.understanding.coverage, 0)
        XCTAssertTrue(report.understanding.correct.isEmpty)
        XCTAssertEqual(report.language.grammar.count, 1)
        XCTAssertEqual(report.topPriorities, ["важное"])
    }

    func testMissingArraysBecomeEmpty() throws {
        // Модель часто опускает пустые массивы — это не повод падать.
        let report = try ClaudeClient.decodeReport(
            from: "{\"understanding\": {\"coverage\": 0.6}}")
        XCTAssertEqual(report.understanding.coverage, 0.6)
        XCTAssertTrue(report.understanding.missed.isEmpty)
        XCTAssertTrue(report.language.suggestedWords.isEmpty)
        XCTAssertTrue(report.topPriorities.isEmpty)
    }

    func testCheapModelSkipsUnsupportedParameters() {
        // Haiku не принимает adaptive-рассуждение и параметр усилия —
        // запрос с ними вернул бы ошибку вместо разбора.
        XCTAssertFalse(ClaudeModel.haiku45.supportsAdaptiveThinking)
        XCTAssertTrue(ClaudeModel.opus5.supportsAdaptiveThinking)
        XCTAssertTrue(ClaudeModel.sonnet5.supportsAdaptiveThinking)
    }

    // MARK: - Учёт расходов

    func testUsageIsPricedByModel() {
        let record = ClaudeClient.usageRecord(
            from: response([], input: 13_600, output: 1_500), model: "claude-opus-5")

        XCTAssertEqual(record.inputTokens, 13_600)
        XCTAssertEqual(record.outputTokens, 1_500)
        XCTAssertEqual(record.cost, 0.1055, accuracy: 0.0001)
    }

    func testCheaperModelIsRecordedCheaper() {
        let payload = response([], input: 13_600, output: 1_500)
        let opus = ClaudeClient.usageRecord(from: payload, model: "claude-opus-5")
        let haiku = ClaudeClient.usageRecord(from: payload, model: "claude-haiku-4-5")
        XCTAssertLessThan(haiku.cost, opus.cost)
    }

    func testMissingUsageDoesNotCrash() {
        let record = ClaudeClient.usageRecord(from: [:], model: "claude-opus-5")
        XCTAssertEqual(record.inputTokens, 0)
        XCTAssertEqual(record.cost, 0)
    }

    // MARK: - Ошибки

    func testReadsServerErrorMessage() {
        let payload = Data("""
        {"type":"error","error":{"type":"invalid_request_error","message":"credit balance is too low"}}
        """.utf8)
        XCTAssertEqual(ClaudeClient.errorMessage(from: payload), "credit balance is too low")
    }

    func testFallsBackToRawBody() {
        XCTAssertEqual(ClaudeClient.errorMessage(from: Data("Gateway timeout".utf8)),
                       "Gateway timeout")
    }

    func testMissingKeyIsExplained() {
        let message = ClaudeClientError.noAPIKey.localizedDescription
        XCTAssertTrue(message.contains("настройках"))
    }

    func testBudgetErrorShowsNumbers() {
        let message = ClaudeClientError
            .budgetExceeded(spent: 10.5, limit: 10).localizedDescription
        XCTAssertTrue(message.contains("10.50"))
        XCTAssertTrue(message.contains("10.00"))
    }
}
