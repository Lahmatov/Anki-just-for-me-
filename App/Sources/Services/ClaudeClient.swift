import Foundation
import AJFMCore

enum ClaudeClientError: LocalizedError {
    case noAPIKey
    case budgetExceeded(spent: Double, limit: Double)
    case http(status: Int, message: String)
    case emptyResponse
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Не задан ключ API — добавь его в настройках."
        case .budgetExceeded(let spent, let limit):
            return String(
                format: "Месячный лимит исчерпан: потрачено $%.2f из $%.2f.", spent, limit)
        case .http(let status, let message):
            return "Сервер ответил \(status): \(message)"
        case .emptyResponse:
            return "Модель вернула пустой ответ."
        case .badJSON(let detail):
            return "Не удалось разобрать ответ модели: \(detail)"
        }
    }
}

/// Клиент Claude API для разбора пересказов.
///
/// Официального SDK для Swift нет, поэтому работаем с HTTP напрямую.
struct ClaudeClient {
    var apiKey: String
    var model: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    /// Итог запроса. Расход учитывается всегда — даже если ответ не удалось
    /// разобрать: запрос уже оплачен, и не посчитать его значит незаметно
    /// сломать месячный лимит.
    struct Outcome {
        var usage: UsageRecord
        var report: RetellReport?
        var rawText: String
        var decodeError: String?
    }

    func analyze(
        subtitles: String,
        retell: String,
        episodeTitle: String?,
        watchedUpTo: TimeInterval?
    ) async throws -> Outcome {
        guard !apiKey.isEmpty else { throw ClaudeClientError.noAPIKey }

        let userMessage = RetellPrompt.userMessage(
            subtitles: subtitles, retell: retell,
            episodeTitle: episodeTitle, watchedUpTo: watchedUpTo)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 8_000,
            "system": RetellPrompt.system,
            "messages": [["role": "user", "content": userMessage]],
        ]
        // Разбор пересказа — задача с рассуждением: модель сверяет утверждения
        // с субтитрами и подбирает цитаты. Но самые дешёвые модели этих
        // параметров не принимают вовсе и вернут ошибку.
        if ClaudeModel.pricing(for: model).supportsAdaptiveThinking {
            body["thinking"] = ["type": "adaptive"]
            body["output_config"] = ["effort": "high"]
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeClientError.http(
                status: http.statusCode,
                message: Self.errorMessage(from: data))
        }

        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let usage = Self.usageRecord(from: parsed, model: model)

        guard let text = Self.extractText(from: parsed), !text.isEmpty else {
            return Outcome(
                usage: usage, report: nil, rawText: "",
                decodeError: ClaudeClientError.emptyResponse.localizedDescription)
        }

        do {
            return Outcome(
                usage: usage, report: try Self.decodeReport(from: text),
                rawText: text, decodeError: nil)
        } catch {
            return Outcome(
                usage: usage, report: nil, rawText: text,
                decodeError: error.localizedDescription)
        }
    }

    // MARK: - Разбор ответа

    /// Ответ может содержать блоки размышлений — берём только текстовые.
    static func extractText(from response: [String: Any]) -> String? {
        guard let content = response["content"] as? [[String: Any]] else { return nil }
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return text.isEmpty ? nil : text
    }

    /// Модель просят вернуть чистый JSON, но она может обернуть его в markdown
    /// или добавить фразу до. Вырезаем объект по внешним скобкам.
    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    static func decodeReport(from text: String) throws -> RetellReport {
        guard let json = extractJSONObject(from: text) else {
            throw ClaudeClientError.badJSON("в ответе нет JSON-объекта")
        }
        do {
            return try JSONDecoder().decode(RetellReport.self, from: Data(json.utf8))
        } catch {
            throw ClaudeClientError.badJSON(error.localizedDescription)
        }
    }

    static func usageRecord(from response: [String: Any], model: String) -> UsageRecord {
        let usage = response["usage"] as? [String: Any] ?? [:]
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let pricing = ClaudeModel.pricing(for: model)
        return UsageRecord(
            date: Date(), model: model, inputTokens: input, outputTokens: output,
            cost: pricing.cost(inputTokens: input, outputTokens: output))
    }

    static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8) ?? "неизвестная ошибка"
        }
        return message
    }
}
