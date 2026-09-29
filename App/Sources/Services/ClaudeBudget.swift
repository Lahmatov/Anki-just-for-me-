import Foundation
import SwiftData
import AJFMCore

/// Выбранная модель и месячный лимит — общие для всех запросов к Claude.
///
/// Разбор пересказа и набор по запросу тратят один бюджет: если бы у
/// каждой функции был свой счётчик, лимит в €10 превратился бы в €20.
@MainActor
struct ClaudeBudget {
    let context: ModelContext

    static let defaultLimit = 10.0

    var model: ModelPricing {
        ClaudeModel.pricing(
            for: UserDefaults.standard.string(forKey: SettingsKey.claudeModel)
                ?? ClaudeModel.opus5.id)
    }

    /// Модель для наборов слов. Подбор слов — несложная задача: Haiku
    /// справляется за секунды и стоит в разы меньше Opus (цент-два за набор
    /// против двадцати). Разбор пересказа — другое дело, там своя настройка.
    var deckModel: ModelPricing {
        ClaudeModel.pricing(
            for: UserDefaults.standard.string(forKey: SettingsKey.deckModel)
                ?? ClaudeModel.haiku45.id)
    }

    var monthlyLimit: Double {
        let stored = UserDefaults.standard.double(forKey: SettingsKey.monthlyBudget)
        return stored > 0 ? stored : Self.defaultLimit
    }

    var usage: UsageSummary {
        let records = ((try? context.fetch(FetchDescriptor<UsageEntry>())) ?? [])
            .map(\.asRecord)
        return UsageTracker.summary(records: records, limit: monthlyLimit)
    }

    /// Ключ выбранного провайдера ИИ (см. `AIKeys`).
    var apiKey: String? { AIKeys.key(for: AIKeys.active) }

    /// Месячный лимит в долларах считается только для Claude: цены других
    /// провайдеров приложение не знает, их лимит ставится в их консоли.
    var tracksCost: Bool { AIKeys.active.tracksCost }

    func canAfford(inputTokens: Int, outputTokens: Int) -> Bool {
        UsageTracker.canAfford(
            estimatedInputTokens: inputTokens, estimatedOutputTokens: outputTokens,
            pricing: model, summary: usage)
    }

    /// Запрос оплачен независимо от того, пригодился ли ответ, — поэтому
    /// расход записывается сразу и всегда.
    func record(_ usage: UsageRecord, purpose: String) {
        context.insert(UsageEntry(record: usage))
        try? context.save()
        Log.info(
            .network, purpose + ": " + String(format: "$%.4f", usage.cost),
            detail: "модель: \(usage.model), вход: \(usage.inputTokens) токенов, "
                + "выход: \(usage.outputTokens)")
    }
}
