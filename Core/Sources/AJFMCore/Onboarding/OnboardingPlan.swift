import Foundation

/// Шаг знакомства с приложением.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    /// Знакомство с лосем Мончиком: кто это и зачем приложение.
    case welcome
    /// Язык интерфейса и переводов. Первым: всё остальное читается на нём.
    case language
    /// Как вообще устроен главный контур.
    case howItWorks
    /// Короткий тест словаря — от уровня зависит, какие слова подбирать.
    case level
    /// Какой сериал учим: по нему строится карта, и первые слова — из него.
    case show
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
        case .welcome: return tr("Привет", "Olá", "Hi")
        case .language: return tr("Язык", "Idioma", "Language")
        case .howItWorks: return tr("Как это работает", "Como funciona", "How it works")
        case .level: return tr("Уровень", "Nível", "Level")
        case .show: return tr("Сериал", "Série", "Show")
        case .starterDeck: return tr("С чего начать", "Por onde começar", "Where to start")
        case .voice: return tr("Голос", "Voz", "Voice")
        case .goal: return tr("Зачем это всё", "Para quê", "What for")
        case .reminder: return tr("Когда", "Quando", "When")
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
        hasLevel: Bool = true,
        hasStudyShow: Bool = true
    ) -> OnboardingPlan {
        // Приветствие всегда первое: даже вернувшемуся из настроек короткое
        // «кто я и что тут» не мешает, а в первый запуск без него шаги
        // настройки выглядят анкетой ни о чём.
        var steps: [OnboardingStep] = [.welcome]

        // Язык спрашиваем, пока его не выбрали явно: системный подставлен
        // заранее, так что шаг — одно подтверждение.
        if !hasChosenLanguage { steps.append(.language) }
        steps.append(.howItWorks)
        // Уровень — до стартового набора и целей: от него зависит, какие
        // слова предлагать.
        if !hasLevel { steps.append(.level) }
        // Сериал — после уровня и до стартового набора: выбранный сериал сам
        // даёт первые слова, и стартовый набор тогда уже не нужен.
        if !hasStudyShow { steps.append(.show) }
        if !hasWords { steps.append(.starterDeck) }
        // Про голос говорим, только если система выдаёт сжатый: иначе это
        // совет починить то, что не сломано.
        if needsBetterVoice { steps.append(.voice) }
        if !hasGoal { steps.append(.goal) }
        if !hasReminder { steps.append(.reminder) }

        return OnboardingPlan(steps: steps)
    }

    /// Версия знакомства. Растёт, когда знакомство меняется настолько, что
    /// его стоит показать заново и тем, кто прошёл прежнее: так новый дизайн
    /// с маскотом увидят и на уже установленном приложении.
    public static let currentVersion = 3

    /// Какую версию знакомства человек уже видел. До версий хранился только
    /// флаг «пройдено» — он означает первую версию.
    public static func seenVersion(stored: Int, legacyDone: Bool) -> Int {
        max(stored, legacyDone ? 1 : 0)
    }

    /// Показывать ли знакомство при запуске.
    public static func shouldShow(seenVersion: Int) -> Bool {
        seenVersion < currentVersion
    }

    /// Первый запуск: база пуста, ничего не настроено.
    public static var firstLaunch: OnboardingPlan {
        OnboardingPlan(steps: OnboardingStep.allCases)
    }
}
