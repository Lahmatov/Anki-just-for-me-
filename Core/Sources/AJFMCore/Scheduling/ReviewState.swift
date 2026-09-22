import Foundation

/// Оценка, которую пользователь ставит себе после показа ответа.
public enum Grade: Int, Codable, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var title: String {
        switch self {
        case .again: return "Забыл"
        case .hard: return "Трудно"
        case .good: return "Хорошо"
        case .easy: return "Легко"
        }
    }
}

public enum LearningState: String, Codable, CaseIterable, Sendable {
    case new, learning, review, relearning

    public var title: String {
        switch self {
        case .new: return "Новая"
        case .learning: return "Учится"
        case .review: return "Повторение"
        case .relearning: return "Переучивается"
        }
    }
}

/// Состояние карточки в цикле повторений.
///
/// Поля общие для всех алгоритмов, плюс опциональные под конкретный: `stability`
/// и `difficulty` нужны FSRS, `ease` — SM-2, `box` — Лейтнеру, `streak` — зубрёжке.
/// Единая структура вместо JSON-блоба: так переключение алгоритма на наборе
/// не теряет прогресс и остаётся проверяемым тестами.
public struct ReviewState: Codable, Equatable, Sendable {
    public var state: LearningState
    public var due: Date
    public var lastReview: Date?
    /// Текущий интервал в днях. По нему считается зрелость карточки.
    public var intervalDays: Double
    public var reps: Int
    public var lapses: Int

    /// Номер шага внутри фазы заучивания или переучивания.
    public var step: Int?
    /// FSRS: устойчивость памяти в днях.
    public var stability: Double?
    /// FSRS: сложность карточки, 1...10.
    public var difficulty: Double?
    /// SM-2: коэффициент лёгкости.
    public var ease: Double?
    /// Лейтнер: номер коробки.
    public var box: Int?
    /// Зубрёжка: сколько верных ответов подряд.
    public var streak: Int?

    public init(
        state: LearningState = .new,
        due: Date = Date(),
        lastReview: Date? = nil,
        intervalDays: Double = 0,
        reps: Int = 0,
        lapses: Int = 0,
        step: Int? = nil,
        stability: Double? = nil,
        difficulty: Double? = nil,
        ease: Double? = nil,
        box: Int? = nil,
        streak: Int? = nil
    ) {
        self.state = state
        self.due = due
        self.lastReview = lastReview
        self.intervalDays = intervalDays
        self.reps = reps
        self.lapses = lapses
        self.step = step
        self.stability = stability
        self.difficulty = difficulty
        self.ease = ease
        self.box = box
        self.streak = streak
    }

    /// Порог, с которого слово считается выученным. Решение P-4 в docs/decisions.md:
    /// на этой метрике висят все награды, поэтому она одна на всё приложение.
    public static let matureIntervalDays: Double = 21

    public var isMature: Bool {
        state == .review && intervalDays >= Self.matureIntervalDays
    }
}

/// Сколько целых суток прошло между двумя моментами. Ровно как `timedelta.days`
/// в эталонной реализации FSRS — округление вниз, а не к ближайшему.
func elapsedDays(from start: Date, to end: Date) -> Int {
    Int(floor(end.timeIntervalSince(start) / 86_400))
}
