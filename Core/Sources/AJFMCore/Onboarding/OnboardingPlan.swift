import Foundation

/// Шаг знакомства с приложением.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    /// Как вообще устроен главный контур.
    case howItWorks
    /// Положить в базу стартовый набор, чтобы не встречать пустым экраном.
    case starterDeck
    /// Проверить голос и подсказать, где скачать получше.
    case voice
    /// Завести первую цель с наградой.
    case goal
    /// Когда учиться — напоминание.
    case reminder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .howItWorks: return "Как это работает"
        case .starterDeck: return "С чего начать"
        case .voice: return "Голос"
        case .goal: return "Зачем это всё"
        case .reminder: return "Когда"
        }
    }
}

/// Что показывать при знакомстве.
///
/// Онбординг здесь не рекламный, а настроечный: каждый шаг что-то делает,
/// а не рассказывает. Поэтому шаги, которые уже не нужны — набор есть, голос
/// хороший, цель заведена, — просто не показываются. Человеку, вернувшемуся
/// к знакомству из настроек, незачем листать пустые экраны.
public struct OnboardingPlan: Equatable, Sendable, Identifiable {
    public var steps: [OnboardingStep]

    /// Разные наборы шагов — разные экраны: по идентификатору SwiftUI
    /// понимает, что показывать заново.
    public var id: String { steps.map(\.rawValue).joined(separator: "-") }

    public var isEmpty: Bool { steps.isEmpty }
    public var count: Int { steps.count }

    public init(steps: [OnboardingStep]) {
        self.steps = steps
    }

    public static func make(
        hasWords: Bool,
        needsBetterVoice: Bool,
        hasGoal: Bool,
        hasReminder: Bool
    ) -> OnboardingPlan {
        var steps: [OnboardingStep] = [.howItWorks]

        if !hasWords { steps.append(.starterDeck) }
        // Про голос говорим, только если система выдаёт сжатый: иначе это
        // совет починить то, что не сломано.
        if needsBetterVoice { steps.append(.voice) }
        if !hasGoal { steps.append(.goal) }
        if !hasReminder { steps.append(.reminder) }

        return OnboardingPlan(steps: steps)
    }

    /// Первый запуск: база пуста, ничего не настроено.
    public static var firstLaunch: OnboardingPlan {
        OnboardingPlan(steps: OnboardingStep.allCases)
    }
}
