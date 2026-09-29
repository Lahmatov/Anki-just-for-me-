import Foundation

/// Провайдеры ИИ, чей ключ можно вписать в приложение.
///
/// Claude — родной: запросы идут в Messages API с разметкой ответа по
/// JSON-схеме и учётом стоимости. Остальные говорят на протоколе OpenAI
/// Chat Completions — его поддерживают все они, поэтому клиент один, а
/// различаются адрес, модель по умолчанию и то, насколько строго провайдер
/// умеет держать формат ответа.
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case anthropic
    case openai
    case gemini
    case kimi
    case deepseek
    case mistral
    case xai
    case qwen

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        case .kimi: return "Kimi (Moonshot AI)"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .xai: return "Grok (xAI)"
        case .qwen: return "Qwen (Alibaba Cloud)"
        }
    }

    /// Короткое имя для подписей «Набор через …».
    public var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .kimi: return "Kimi"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .xai: return "Grok"
        case .qwen: return "Qwen"
        }
    }

    /// Полный адрес запроса.
    public var endpoint: URL {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .kimi: return URL(string: "https://api.moonshot.ai/v1/chat/completions")!
        case .deepseek: return URL(string: "https://api.deepseek.com/chat/completions")!
        case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")!
        case .xai: return URL(string: "https://api.x.ai/v1/chat/completions")!
        case .qwen:
            return URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")!
        }
    }

    /// Модель по умолчанию — быстрая и недорогая. Названия моделей у
    /// провайдеров меняются каждые несколько месяцев, поэтому модель можно
    /// вписать свою; где возможно, взят «вечный» псевдоним (`-latest`).
    public var defaultModel: String {
        switch self {
        case .anthropic: return ClaudeModel.haiku45.id
        case .openai: return "gpt-5-mini"
        case .gemini: return "gemini-2.5-flash"
        case .kimi: return "kimi-k2.6"
        case .deepseek: return "deepseek-chat"
        case .mistral: return "mistral-small-latest"
        case .xai: return "grok-4.3"
        case .qwen: return "qwen-plus"
        }
    }

    /// Где получить ключ.
    public var consoleURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .kimi: return URL(string: "https://platform.moonshot.ai/console/api-keys")!
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")!
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")!
        case .xai: return URL(string: "https://console.x.ai")!
        case .qwen: return URL(string: "https://modelstudio.console.alibabacloud.com")!
        }
    }

    /// Как провайдер держит формат ответа.
    public enum OutputFormat: Equatable, Sendable {
        /// Ответ по JSON-схеме — разбирается всегда.
        case jsonSchema
        /// Только «какой-нибудь JSON-объект»: схема уходит текстом в инструкцию.
        case jsonObject
    }

    public var outputFormat: OutputFormat {
        switch self {
        case .anthropic, .openai, .gemini, .mistral, .xai: return .jsonSchema
        case .kimi, .deepseek, .qwen: return .jsonObject
        }
    }

    /// Новые модели OpenAI не принимают `max_tokens` — только
    /// `max_completion_tokens`; остальные понимают старое имя.
    public var maxTokensKey: String {
        self == .openai ? "max_completion_tokens" : "max_tokens"
    }

    /// Имя записи в Keychain. У Claude — прежнее, чтобы уже вписанный ключ
    /// не потерялся после обновления.
    public var keychainAccount: String {
        self == .anthropic ? "claude-api-key" : "ai-key-" + rawValue
    }

    /// Стоимость запроса считается только у Claude: цены остальных меняются
    /// чаще, чем выходят версии приложения, и неверная цифра хуже никакой.
    public var tracksCost: Bool { self == .anthropic }
}
