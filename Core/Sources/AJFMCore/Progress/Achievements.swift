import Foundation

/// Сводка достижений пользователя, по которой считаются ачивки.
public struct LearningStats: Equatable, Sendable {
    public var matureWords: Int
    public var totalWords: Int
    /// Повторы, сделанные в сессии, — правки руками сюда не идут.
    public var honestReviews: Int
    public var currentStreakDays: Int
    public var retellCount: Int
    public var bestRetellCoverage: Double
    public var pronunciationStreak: Int
    public var perfectSessions: Int

    public init(
        matureWords: Int = 0, totalWords: Int = 0, honestReviews: Int = 0,
        currentStreakDays: Int = 0, retellCount: Int = 0, bestRetellCoverage: Double = 0,
        pronunciationStreak: Int = 0, perfectSessions: Int = 0
    ) {
        self.matureWords = matureWords
        self.totalWords = totalWords
        self.honestReviews = honestReviews
        self.currentStreakDays = currentStreakDays
        self.retellCount = retellCount
        self.bestRetellCoverage = bestRetellCoverage
        self.pronunciationStreak = pronunciationStreak
        self.perfectSessions = perfectSessions
    }
}

public struct Achievement: Equatable, Sendable, Identifiable {
    public enum Metric: String, Sendable {
        case matureWords, honestReviews, streakDays, retellCount
        case retellCoverage, pronunciationStreak, perfectSessions
    }

    public var id: String
    public var title: String
    public var detail: String
    public var metric: Metric
    public var threshold: Double
    public var symbol: String

    public func value(in stats: LearningStats) -> Double {
        switch metric {
        case .matureWords: return Double(stats.matureWords)
        case .honestReviews: return Double(stats.honestReviews)
        case .streakDays: return Double(stats.currentStreakDays)
        case .retellCount: return Double(stats.retellCount)
        case .retellCoverage: return stats.bestRetellCoverage
        case .pronunciationStreak: return Double(stats.pronunciationStreak)
        case .perfectSessions: return Double(stats.perfectSessions)
        }
    }

    public func isUnlocked(by stats: LearningStats) -> Bool {
        value(in: stats) >= threshold
    }

    public func progress(in stats: LearningStats) -> Double {
        threshold <= 0 ? 1 : min(1, value(in: stats) / threshold)
    }
}

/// Ачивки за осмысленные вехи.
///
/// Их нарочно мало: полсотни бейджей ни за что обесценивают все остальные.
/// И ни одна не выдаётся за количество кликов — только за результат.
public enum AchievementCatalog {

    public static let all: [Achievement] = [
        Achievement(
            id: "mature-10", title: "Первый десяток",
            detail: "10 слов дожили до долгосрочной памяти",
            metric: .matureWords, threshold: 10, symbol: "leaf"),
        Achievement(
            id: "mature-50", title: "Полсотни",
            detail: "50 слов в долгосрочной памяти",
            metric: .matureWords, threshold: 50, symbol: "tree"),
        Achievement(
            id: "mature-150", title: "Сто пятьдесят",
            detail: "150 слов — обычный размер первой серьёзной цели",
            metric: .matureWords, threshold: 150, symbol: "books.vertical"),
        Achievement(
            id: "mature-500", title: "Пятьсот",
            detail: "500 слов в долгосрочной памяти",
            metric: .matureWords, threshold: 500, symbol: "graduationcap"),
        Achievement(
            id: "mature-1000", title: "Тысяча",
            detail: "На этом словаре уже смотрят сериалы без субтитров",
            metric: .matureWords, threshold: 1000, symbol: "crown"),

        Achievement(
            id: "streak-7", title: "Неделя подряд",
            detail: "7 учебных дней без пропусков",
            metric: .streakDays, threshold: 7, symbol: "calendar"),
        Achievement(
            id: "streak-30", title: "Месяц подряд",
            detail: "30 учебных дней без пропусков",
            metric: .streakDays, threshold: 30, symbol: "calendar.badge.checkmark"),

        Achievement(
            id: "reviews-1000", title: "Тысяча повторов",
            detail: "1000 честных повторений в сессиях",
            metric: .honestReviews, threshold: 1000, symbol: "arrow.triangle.2.circlepath"),

        Achievement(
            id: "retell-1", title: "Первый пересказ",
            detail: "Рассказал серию по-английски вслух",
            metric: .retellCount, threshold: 1, symbol: "text.bubble"),
        Achievement(
            id: "retell-10", title: "Десять пересказов",
            detail: "Десять серий пересказаны вслух",
            metric: .retellCount, threshold: 10, symbol: "person.wave.2"),
        Achievement(
            id: "retell-coverage-80", title: "Понял почти всё",
            detail: "Пересказ покрыл 80% событий серии",
            metric: .retellCoverage, threshold: 0.8, symbol: "eye"),

        Achievement(
            id: "pronunciation-20", title: "Двадцать подряд",
            detail: "20 минимальных пар подряд без ошибки",
            metric: .pronunciationStreak, threshold: 20, symbol: "waveform"),

        Achievement(
            id: "perfect-10", title: "Десять чистых сессий",
            detail: "10 сессий без единой ошибки",
            metric: .perfectSessions, threshold: 10, symbol: "checkmark.seal"),
    ]

    public static func unlocked(for stats: LearningStats) -> [Achievement] {
        all.filter { $0.isUnlocked(by: stats) }
    }

    public static func locked(for stats: LearningStats) -> [Achievement] {
        all.filter { !$0.isUnlocked(by: stats) }
    }

    /// Ближайшая цель — что показать как «осталось чуть-чуть».
    public static func next(for stats: LearningStats) -> Achievement? {
        locked(for: stats).max { $0.progress(in: stats) < $1.progress(in: stats) }
    }
}
