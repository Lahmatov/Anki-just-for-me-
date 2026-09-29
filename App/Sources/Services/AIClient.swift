import Foundation
import AJFMCore

/// Ключи ИИ и выбранный провайдер.
///
/// Ключи — только в Keychain, по записи на провайдера: вписать можно
/// несколько, работает выбранный. Модель у каждого своя и её можно
/// поменять — у провайдеров названия моделей устаревают быстро.
@MainActor
enum AIKeys {
    static var active: AIProvider {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.aiProvider)
                .flatMap(AIProvider.init(rawValue:)) ?? .anthropic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKey.aiProvider) }
    }

    static func key(for provider: AIProvider) -> String? {
        guard let key = Keychain.get(provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    static func setKey(_ key: String, for provider: AIProvider) {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainAccount)
    }

    /// Модель для запросов этого провайдера. У Claude своя настройка по
    /// задачам (наборы, разборы) — здесь для остальных.
    static func model(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: SettingsKey.aiModelPrefix + provider.rawValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? provider.defaultModel : stored
    }

    static func setModel(_ model: String, for provider: AIProvider) {
        UserDefaults.standard.set(model, forKey: SettingsKey.aiModelPrefix + provider.rawValue)
    }

    static var hasActiveKey: Bool { key(for: active) != nil }

    /// Все ключи — часть «Удалить все данные».
    static func eraseAll() {
        for provider in AIProvider.allCases { Keychain.remove(provider.keychainAccount) }
    }
}

/// Запрос к ИИ по своему ключу — к тому провайдеру, что выбран.
///
/// Экраны строят один и тот же `ClaudeRequest`; для Claude он уходит как
/// есть, для остальных переводится в Chat Completions (`ChatCompletions`).
/// Ответ в обоих случаях — `ClaudeClient.Completion`: текст, расход и
/// причина остановки, — так что разбор ответа у экранов не меняется.
@MainActor
struct AIClient {
    let provider: AIProvider
    let apiKey: String

    /// Клиент выбранного провайдера или nil, если ключа нет.
    static func current() -> AIClient? {
        let provider = AIKeys.active
        guard let key = AIKeys.key(for: provider) else { return nil }
        return AIClient(provider: provider, apiKey: key)
    }

    func complete(_ request: ClaudeRequest) async throws -> ClaudeClient.Completion {
        if provider == .anthropic {
            return try await ClaudeClient(apiKey: apiKey, model: request.model.id).complete(request)
        }
        let model = AIKeys.model(for: provider)
        var urlRequest = URLRequest(url: provider.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 180
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: ChatCompletions.body(for: request, provider: provider, model: model))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeClientError.http(
                status: http.statusCode,
                message: ChatCompletions.errorMessage(from: data)
                    ?? String(data: data, encoding: .utf8)
                    ?? tr("неизвестная ошибка", "erro desconhecido", "unknown error"))
        }
        let parsed: ChatCompletions.Response
        do {
            parsed = try ChatCompletions.parse(data)
        } catch {
            throw ClaudeClientError.badJSON(tr("ответ провайдера не JSON", "a resposta não é JSON",
                                               "the provider's reply isn't JSON"))
        }
        // Цену других провайдеров не считаем (AIProvider.tracksCost): токены
        // записываются, а деньги — ноль, чтобы месячный лимит Claude не врал.
        let usage = UsageRecord(date: Date(), model: provider.shortName + " · " + model,
                                inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens,
                                cost: 0)
        return ClaudeClient.Completion(text: parsed.text, usage: usage, stopReason: parsed.stopReason)
    }

    /// Разбор пересказа — тот же запрос, что у `ClaudeClient.analyze`.
    func analyze(reference: RetellReference, retell: String, episodeTitle: String?,
                 modelID: String, watchedUpTo: TimeInterval?) async throws -> ClaudeClient.Outcome {
        let completion = try await complete(ClaudeRequest(
            model: ClaudeModel.pricing(for: modelID),
            system: RetellPrompt.system(for: Loc.language, reference: reference),
            userMessage: RetellPrompt.userMessage(
                reference: reference, retell: retell,
                episodeTitle: episodeTitle, watchedUpTo: watchedUpTo),
            maxTokens: 16_000,
            effort: .high))
        if let problem = ClaudeClient.problem(with: completion) {
            return ClaudeClient.Outcome(usage: completion.usage, report: nil,
                                        rawText: completion.text ?? "", decodeError: problem)
        }
        let text = completion.text ?? ""
        do {
            return ClaudeClient.Outcome(usage: completion.usage,
                                        report: try ClaudeClient.decodeReport(from: text),
                                        rawText: text, decodeError: nil)
        } catch {
            return ClaudeClient.Outcome(usage: completion.usage, report: nil, rawText: text,
                                        decodeError: error.localizedDescription)
        }
    }

    /// Проверка ключа одним крошечным запросом: лучше узнать о неверном
    /// ключе сейчас, чем посреди набора слов.
    func ping() async throws {
        let completion = try await complete(ClaudeRequest(
            model: ClaudeModel.haiku45, system: "Reply with the single word OK.",
            userMessage: "Ping", maxTokens: 16, effort: .low))
        if completion.text == nil, completion.stopReason != .truncated {
            throw ClaudeClientError.emptyResponse
        }
    }
}
