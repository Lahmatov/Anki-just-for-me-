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

    /// Вычисляемое, а не хранимое: названия зависят от языка интерфейса.
    public static var all: [Achievement] { [
        Achievement(
            id: "mature-10", title: tr("Первый десяток", "Primeira dezena", "First ten"),
            detail: tr("10 слов дожили до долгосрочной памяти",
                       "10 palavras chegaram à memória de longo prazo",
                       "10 words made it to long-term memory"),
            metric: .matureWords, threshold: 10, symbol: "leaf"),
        Achievement(
            id: "mature-50", title: tr("Полсотни", "Meia centena", "Fifty"),
            detail: tr("50 слов в долгосрочной памяти",
                       "50 palavras na memória de longo prazo",
                       "50 words in long-term memory"),
            metric: .matureWords, threshold: 50, symbol: "tree"),
        Achievement(
            id: "mature-150", title: tr("Сто пятьдесят", "Cento e cinquenta", "A hundred and fifty"),
            detail: tr("150 слов — обычный размер первой серьёзной цели",
                       "150 palavras — o tamanho habitual do primeiro objetivo a sério",
                       "150 words — the usual size of a first serious goal"),
            metric: .matureWords, threshold: 150, symbol: "books.vertical"),
        Achievement(
            id: "mature-500", title: tr("Пятьсот", "Quinhentas", "Five hundred"),
            detail: tr("500 слов в долгосрочной памяти",
                       "500 palavras na memória de longo prazo",
                       "500 words in long-term memory"),
            metric: .matureWords, threshold: 500, symbol: "graduationcap"),
        Achievement(
            id: "mature-1000", title: tr("Тысяча", "Mil", "A thousand"),
            detail: tr("На этом словаре уже смотрят сериалы без субтитров",
                       "Com este vocabulário já se veem séries sem legendas",
                       "With this vocabulary people watch shows without subtitles"),
            metric: .matureWords, threshold: 1000, symbol: "crown"),

        Achievement(
            id: "streak-7", title: tr("Неделя подряд", "Uma semana seguida", "A week in a row"),
            detail: tr("7 учебных дней без пропусков",
                       "7 dias de estudo sem falhas",
                       "7 study days without a gap"),
            metric: .streakDays, threshold: 7, symbol: "calendar"),
        Achievement(
            id: "streak-30", title: tr("Месяц подряд", "Um mês seguido", "A month in a row"),
            detail: tr("30 учебных дней без пропусков",
                       "30 dias de estudo sem falhas",
                       "30 study days without a gap"),
            metric: .streakDays, threshold: 30, symbol: "calendar.badge.checkmark"),

        Achievement(
            id: "reviews-1000", title: tr("Тысяча повторов", "Mil revisões", "A thousand reviews"),
            detail: tr("1000 честных повторений в сессиях",
                       "1000 revisões honestas em sessões",
                       "1000 honest reviews in sessions"),
            metric: .honestReviews, threshold: 1000, symbol: "arrow.triangle.2.circlepath"),

        Achievement(
            id: "retell-1", title: tr("Первый пересказ", "Primeiro reconto", "First retelling"),
            detail: tr("Рассказал серию по-английски вслух",
                       "Contaste um episódio em inglês, em voz alta",
                       "Retold an episode out loud in English"),
            metric: .retellCount, threshold: 1, symbol: "text.bubble"),
        Achievement(
            id: "retell-10", title: tr("Десять пересказов", "Dez recontos", "Ten retellings"),
            detail: tr("Десять серий пересказаны вслух",
                       "Dez episódios recontados em voz alta",
                       "Ten episodes retold out loud"),
            metric: .retellCount, threshold: 10, symbol: "person.wave.2"),
        Achievement(
            id: "retell-coverage-80", title: tr("Понял почти всё", "Percebeste quase tudo", "Got almost everything"),
            detail: tr("Пересказ покрыл 80% событий серии",
                       "O reconto cobriu 80% dos acontecimentos do episódio",
                       "The retelling covered 80% of the episode"),
            metric: .retellCoverage, threshold: 0.8, symbol: "eye"),

        Achievement(
            id: "pronunciation-20", title: tr("Двадцать подряд", "Vinte seguidos", "Twenty in a row"),
            detail: tr("20 минимальных пар подряд без ошибки",
                       "20 pares mínimos seguidos sem erro",
                       "20 minimal pairs in a row without a mistake"),
            metric: .pronunciationStreak, threshold: 20, symbol: "waveform"),

        Achievement(
            id: "perfect-10", title: tr("Десять чистых сессий", "Dez sessões limpas", "Ten clean sessions"),
            detail: tr("10 сессий без единой ошибки",
                       "10 sessões sem um único erro",
                       "10 sessions without a single mistake"),
            metric: .perfectSessions, threshold: 10, symbol: "checkmark.seal"),
    ] }

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
