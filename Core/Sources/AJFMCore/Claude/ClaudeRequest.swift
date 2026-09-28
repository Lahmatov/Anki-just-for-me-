import Foundation

/// Тело запроса к Messages API.
///
/// Вынесено из сетевого клиента, чтобы проверять без сети: неверный
/// параметр для конкретной модели — это ошибка 400 и потерянная попытка,
/// а у разных моделей разный набор допустимых параметров.
public struct ClaudeRequest: Sendable {
    public enum Effort: String, Sendable {
        case low, medium, high
    }

    /// Реплика разговора: для бесед из нескольких ходов.
    public struct Turn: Equatable, Sendable {
        public enum Role: String, Sendable { case user, assistant }
        public var role: Role
        public var text: String

        public init(_ role: Role, _ text: String) {
            self.role = role
            self.text = text
        }
    }

    public var model: ModelPricing
    public var system: String
    public var userMessage: String
    public var maxTokens: Int
    public var effort: Effort
    /// JSON Schema ответа. С ней ответ гарантированно разбирается.
    public var outputSchemaJSON: String?
    /// История разговора. Пустая — запрос из одного сообщения `userMessage`.
    public var conversation: [Turn] = []

    /// Бета-заголовок серверных повторов при отказе классификатора.
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public init(
        model: ModelPricing, system: String, userMessage: String, maxTokens: Int,
        effort: Effort = .high, outputSchemaJSON: String? = nil
    ) {
        self.model = model
        self.system = system
        self.userMessage = userMessage
        self.maxTokens = maxTokens
        self.effort = effort
        self.outputSchemaJSON = outputSchemaJSON
    }

    /// Запрос-разговор: система и история реплик.
    public init(
        model: ModelPricing, system: String, conversation: [Turn], maxTokens: Int,
        effort: Effort = .low, outputSchemaJSON: String? = nil
    ) {
        self.init(model: model, system: system, userMessage: "", maxTokens: maxTokens,
                  effort: effort, outputSchemaJSON: outputSchemaJSON)
        self.conversation = conversation
    }

    /// Что уходит в `messages`.
    public var messages: [Turn] {
        conversation.isEmpty ? [Turn(.user, userMessage)] : conversation
    }

    /// Значение заголовка `anthropic-beta`, если он нужен.
    public var betaHeader: String? {
        model.supportsServerFallback ? Self.fallbackBeta : nil
    }

    public func body() throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model.id,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]

        var outputConfig: [String: Any] = [:]
        // Рассуждение и уровень усилия понимают не все модели: самые дешёвые
        // вернут на них ошибку.
        if model.supportsAdaptiveThinking {
            body["thinking"] = ["type": "adaptive"]
            outputConfig["effort"] = effort.rawValue
        }
        if let outputSchemaJSON {
            let schema = try JSONSerialization.jsonObject(with: Data(outputSchemaJSON.utf8))
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        if !outputConfig.isEmpty {
            body["output_config"] = outputConfig
        }
        if model.supportsServerFallback {
            body["fallbacks"] = "default"
        }
        return body
    }
}

/// Почему модель остановилась — от этого зависит, можно ли верить тексту.
public enum ClaudeStopReason: Equatable, Sendable {
    case finished
    /// Упёрлись в `max_tokens`: JSON почти наверняка обрезан.
    case truncated
    /// Отказ: классификатор безопасности или сама модель.
    case refused
    case other(String)

    public init(raw: String?) {
        switch raw ?? "end_turn" {
        case "end_turn", "stop_sequence": self = .finished
        case "max_tokens": self = .truncated
        case "refusal": self = .refused
        case let value: self = .other(value)
        }
    }
}
