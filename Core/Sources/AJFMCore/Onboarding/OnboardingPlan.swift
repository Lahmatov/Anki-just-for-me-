import Foundation

/// Шаг знакомства с приложением.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    /// Язык интерфейса и переводов. Первым: всё остальное читается на нём.
    case language
    /// Как вообще устроен главный контур.
    case howItWorks
    /// Короткий тест словаря — от уровня зависит, какие слова подбирать.
    case level
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
        case .language: return "Язык"
        case .howItWorks: return "Как это работает"
        case .level: return "Уровень"
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
        hasReminder: Bool,
        hasChosenLanguage: Bool = true,
        hasLevel: Bool = true
    ) -> OnboardingPlan {
        var steps: [OnboardingStep] = []

        // Язык спрашиваем, пока его не выбрали явно: системный подставлен
        // заранее, так что шаг — одно подтверждение.
        if !hasChosenLanguage { steps.append(.language) }
        steps.append(.howItWorks)
        // Уровень — до стартового набора и целей: от него зависит, какие
        // слова предлагать.
        if !hasLevel { steps.append(.level) }
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
