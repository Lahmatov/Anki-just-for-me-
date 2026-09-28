import Foundation
import SwiftData
import AJFMCore

/// Единая точка запросов к ИИ, у которых есть готовый смысл: разговор
/// о серии и т. п. Экранам всё равно, куда уходит запрос — напрямую
/// в Anthropic по своему ключу или через сервер Recap по подписке;
/// выбор маршрута живёт здесь.
@MainActor
enum AIService {

    enum AIError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }

    struct DiscussionResult {
        var reply: EpisodeDiscussion.Reply
        var cost: Double
    }

    /// Следующая реплика Мончика.
    static func discuss(
        context: ModelContext, episode: EpisodeContext,
        turns: [EpisodeDiscussion.Turn], retelling: String?
    ) async throws -> DiscussionResult {
        try await discussDirectly(
            context: context, episode: episode, turns: turns, retelling: retelling)
    }

    private static func discussDirectly(
        context: ModelContext, episode: EpisodeContext,
        turns: [EpisodeDiscussion.Turn], retelling: String?
    ) async throws -> DiscussionResult {
        let budget = ClaudeBudget(context: context)
        guard let apiKey = budget.apiKey else { throw ClaudeClientError.noAPIKey }
        // Разговор — короткие реплики: быстрая модель, как для наборов.
        let model = budget.deckModel
        let system = EpisodeDiscussion.system(
            language: Loc.language, level: AppSettings.englishLevel,
            episodeTitle: episode.title,
            reference: episode.synopsis.map { .synopsis($0) }, retelling: retelling)
        let messages = EpisodeDiscussion.messages(for: turns)

        let input = RetellPrompt.estimateTokens(system)
            + messages.reduce(0) { $0 + RetellPrompt.estimateTokens($1.text) }
        let summary = budget.usage
        guard UsageTracker.canAfford(
            estimatedInputTokens: input,
            estimatedOutputTokens: EpisodeDiscussion.estimatedOutputTokens,
            pricing: model, summary: summary) else {
            throw ClaudeClientError.budgetExceeded(spent: summary.monthCost, limit: summary.limit)
        }

        let completion = try await ClaudeClient(apiKey: apiKey, model: model.id)
            .complete(ClaudeRequest(
                model: model, system: system, conversation: messages,
                maxTokens: EpisodeDiscussion.maxTokens, effort: .low,
                outputSchemaJSON: EpisodeDiscussion.outputSchemaJSON))
        budget.record(completion.usage, purpose: "Разговор о серии")

        if let problem = ClaudeClient.problem(with: completion) {
            throw AIError.message(problem)
        }
        do {
            let reply = try EpisodeDiscussion.parseReply(completion.text ?? "")
            return DiscussionResult(reply: reply, cost: completion.usage.cost)
        } catch {
            throw ClaudeClientError.badJSON(tr("реплика не разобралась", "resposta ilegível",
                                               "the reply was unreadable"))
        }
    }
}
