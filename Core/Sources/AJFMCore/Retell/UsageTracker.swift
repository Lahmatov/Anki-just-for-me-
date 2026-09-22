import Foundation

/// Цены на модели Claude, долларов за миллион токенов.
public struct ModelPricing: Equatable, Sendable {
    public var id: String
    public var title: String
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    /// Понимает ли модель adaptive-рассуждение и параметр усилия.
    /// У Haiku их нет — запрос с ними вернёт ошибку.
    public var supportsAdaptiveThinking: Bool

    public init(
        id: String, title: String, inputPerMillion: Double, outputPerMillion: Double,
        supportsAdaptiveThinking: Bool
    ) {
        self.id = id
        self.title = title
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.supportsAdaptiveThinking = supportsAdaptiveThinking
    }

    public func cost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(inputTokens) / 1_000_000 * inputPerMillion
            + Double(outputTokens) / 1_000_000 * outputPerMillion
    }
}

public enum ClaudeModel {
    public static let opus5 = ModelPricing(
        id: "claude-opus-5", title: "Opus 5 — лучший разбор",
        inputPerMillion: 5, outputPerMillion: 25, supportsAdaptiveThinking: true)
    public static let sonnet5 = ModelPricing(
        id: "claude-sonnet-5", title: "Sonnet 5 — втрое дешевле",
        inputPerMillion: 2, outputPerMillion: 10, supportsAdaptiveThinking: true)
    public static let haiku45 = ModelPricing(
        id: "claude-haiku-4-5", title: "Haiku 4.5 — самый дешёвый",
        inputPerMillion: 1, outputPerMillion: 5, supportsAdaptiveThinking: false)

    public static let all = [opus5, sonnet5, haiku45]

    public static func pricing(for id: String) -> ModelPricing {
        all.first { $0.id == id } ?? opus5
    }
}

/// Учёт расходов на облачные разборы.
///
/// Нужен не ради экономии — бюджета хватает с запасом, — а чтобы ошибка
/// в коде (цикл, повторные запросы) не съела месячный лимит молча.
public struct UsageRecord: Codable, Equatable, Sendable {
    public var date: Date
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cost: Double

    public init(date: Date, model: String, inputTokens: Int, outputTokens: Int, cost: Double) {
        self.date = date
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cost = cost
    }
}

public struct UsageSummary: Equatable, Sendable {
    public var monthCost: Double
    public var monthRequests: Int
    public var limit: Double

    public var remaining: Double { max(0, limit - monthCost) }
    public var isOverLimit: Bool { monthCost >= limit }
    public var usedFraction: Double { limit <= 0 ? 0 : min(1, monthCost / limit) }
}

public enum UsageTracker {
    /// Расходы текущего календарного месяца.
    public static func summary(
        records: [UsageRecord], limit: Double, now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSummary {
        let month = records.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        return UsageSummary(
            monthCost: month.reduce(0) { $0 + $1.cost },
            monthRequests: month.count,
            limit: limit)
    }

    /// Хватит ли остатка лимита на запрос такого размера.
    public static func canAfford(
        estimatedInputTokens: Int, estimatedOutputTokens: Int,
        pricing: ModelPricing, summary: UsageSummary
    ) -> Bool {
        let estimate = pricing.cost(
            inputTokens: estimatedInputTokens, outputTokens: estimatedOutputTokens)
        return summary.monthCost + estimate <= summary.limit
    }
}
