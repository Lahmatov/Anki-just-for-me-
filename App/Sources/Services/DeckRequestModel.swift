import Foundation
import SwiftData
import Observation
import AJFMCore

/// «Сделай набор по Friends 1x03» — прямо из приложения, без чата.
@Observable
@MainActor
final class DeckRequestModel {

    enum Step: Equatable {
        case editing
        case working
        case failed(String)
    }

    var topic = ""
    var wordCount = DeckRequest.defaultWordCount
    var level: CEFRLevel? = AppSettings.englishLevel
    private(set) var subtitles: String?
    private(set) var subtitlesName: String?
    private(set) var step: Step = .editing
    private(set) var lastCost: Double = 0

    private let context: ModelContext
    /// Читается один раз: оценка цены пересчитывается на каждую букву в поле,
    /// и ходить за сотнями слов в базу при каждом нажатии незачем.
    private let knownTerms: [String]

    init(context: ModelContext) {
        self.context = context
        self.knownTerms = ImportService(context: context)
            .recentTerms(limit: DeckRequest.knownTermsLimit)
    }

    private var budget: ClaudeBudget { ClaudeBudget(context: context) }

    var hasAPIKey: Bool { budget.apiKey != nil }

    var request: DeckRequest {
        DeckRequest(
            topic: topic, subtitles: subtitles, wordCount: wordCount, level: level,
            language: AppSettings.language, knownTerms: knownTerms)
    }

    var canSubmit: Bool {
        step != .working && (!topic.trimmingCharacters(in: .whitespaces).isEmpty
                             || subtitles != nil)
    }

    /// Оценка до отправки, чтобы цена не была сюрпризом.
    var estimatedCost: Double {
        let request = self.request
        return budget.model.cost(
            inputTokens: request.estimatedInputTokens,
            outputTokens: request.estimatedOutputTokens)
    }

    var usage: UsageSummary { budget.usage }

    // MARK: - Субтитры

    func loadSubtitles(from data: Data, name: String) {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            step = .failed("Не удалось прочитать файл субтитров.")
            return
        }
        // Таймкоды модели не нужны и стоят денег — оставляем только реплики.
        // Если формат не распознался, отдаём текст как есть: это может быть
        // просто скопированный диалог.
        subtitles = (try? SubtitleParser.parse(raw))?.plainText() ?? raw
        subtitlesName = name
        if step != .working { step = .editing }
    }

    func removeSubtitles() {
        subtitles = nil
        subtitlesName = nil
    }

    // MARK: - Запрос

    /// Возвращает план импорта для обычного превью или nil при ошибке
    /// (причина — в `step`).
    func generate() async -> ImportPlan? {
        let request = self.request
        do {
            try request.validate()
        } catch {
            step = .failed(error.localizedDescription)
            return nil
        }
        guard let apiKey = budget.apiKey else {
            step = .failed(ClaudeClientError.noAPIKey.localizedDescription)
            return nil
        }
        guard budget.canAfford(
            inputTokens: request.estimatedInputTokens,
            outputTokens: request.estimatedOutputTokens) else {
            let summary = budget.usage
            step = .failed(ClaudeClientError
                .budgetExceeded(spent: summary.monthCost, limit: summary.limit)
                .localizedDescription)
            return nil
        }

        step = .working
        let model = budget.model
        do {
            let completion = try await ClaudeClient(apiKey: apiKey, model: model.id)
                .complete(ClaudeRequest(
                    model: model,
                    system: request.system,
                    userMessage: request.userMessage,
                    maxTokens: DeckRequest.maxTokens,
                    // Подбор слов — не головоломка: среднего усилия хватает,
                    // а ответ приходит заметно быстрее.
                    effort: .medium,
                    outputSchemaJSON: DeckRequest.outputSchemaJSON))

            budget.record(completion.usage, purpose: "Набор по запросу")
            lastCost = completion.usage.cost

            if let problem = ClaudeClient.problem(with: completion) {
                step = .failed(problem)
                return nil
            }
            let file = try request.deckFile(fromResponse: completion.text ?? "")
            let plan = try ImportService(context: context).makePlan(from: file)
            Log.info(
                .importing, "Набор от Claude получен",
                detail: "«\(file.deck.name)», слов: \(file.notes.count)")
            step = .editing
            return plan
        } catch {
            Log.failure(.network, "Набор по запросу не получился", error)
            step = .failed(error.localizedDescription)
            return nil
        }
    }
}
