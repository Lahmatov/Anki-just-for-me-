import Foundation

/// Протокол OpenAI Chat Completions: тело запроса и разбор ответа.
///
/// Тот же `ClaudeRequest` (система, реплики, лимит, схема) переводится в
/// формат, который понимают OpenAI, Gemini, Kimi, DeepSeek, Mistral, Grok и
/// Qwen. Всё без сети — чтобы проверять тестами: неверное поле — это 400 и
/// потерянная попытка человека.
public enum ChatCompletions {

    public static func body(for request: ClaudeRequest, provider: AIProvider, model: String) throws
        -> [String: Any] {
        var system = request.system
        var body: [String: Any] = ["model": model, provider.maxTokensKey: request.maxTokens]

        if let schemaJSON = request.outputSchemaJSON {
            let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))
            switch provider.outputFormat {
            case .jsonSchema:
                body["response_format"] = [
                    "type": "json_schema",
                    "json_schema": ["name": "answer", "schema": schema, "strict": false],
                ]
            case .jsonObject:
                body["response_format"] = ["type": "json_object"]
            }
            // Схема — ещё и текстом: провайдеры с «просто JSON» иначе её не
            // узнают, а режим json_object требует слова «JSON» в инструкции.
            system += "\n\nReply with one JSON object only, matching this JSON Schema:\n" + schemaJSON
        }

        var messages: [[String: String]] = [["role": "system", "content": system]]
        messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        body["messages"] = messages
        return body
    }

    public struct Response: Equatable, Sendable {
        public var text: String?
        public var inputTokens: Int
        public var outputTokens: Int
        public var stopReason: ClaudeStopReason
    }

    public enum ParseError: Error, Equatable {
        case notJSON
    }

    public static func parse(_ data: Data) throws -> Response {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notJSON
        }
        let choice = (object["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]
        let usage = object["usage"] as? [String: Any]
        let text = (message?["content"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let refusal = (message?["refusal"] as? String).map { !$0.isEmpty } ?? false

        let stop: ClaudeStopReason
        if refusal {
            stop = .refused
        } else {
            switch choice?["finish_reason"] as? String {
            case "stop", nil: stop = .finished
            case "length": stop = .truncated
            case "content_filter": stop = .refused
            case let other?: stop = .other(other)
            }
        }
        return Response(
            text: text,
            inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
            outputTokens: usage?["completion_tokens"] as? Int ?? 0,
            stopReason: stop)
    }

    /// Сообщение об ошибке из тела ответа. Gemini иногда оборачивает ошибку
    /// в массив — разбираем оба вида.
    public static func errorMessage(from data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data)
        let root = (object as? [String: Any]) ?? (object as? [[String: Any]])?.first
        if let error = root?["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = root?["message"] as? String { return message }
        return nil
    }
}
