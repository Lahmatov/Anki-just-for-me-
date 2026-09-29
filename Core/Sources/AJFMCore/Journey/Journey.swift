import Foundation

/// Остановка на карте путешествия — круглое число слов.
public struct JourneyStop: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case start
        case step
        /// Веха: круглое число слов, которое стоит отпраздновать.
        case chest
        case finish
    }

    public var index: Int
    /// Сколько слов нужно начать, чтобы дойти сюда.
    public var threshold: Int
    public var kind: Kind

    public var id: Int { index }

    public init(index: Int, threshold: Int, kind: Kind) {
        self.index = index
        self.threshold = threshold
        self.kind = kind
    }

    /// Название остановки: «Старт» или «100 слов».
    public var title: String {
        kind == .start ? tr("Старт", "Partida", "Start") : Counted.words(threshold)
    }

    /// Во что это число слов переводится в сериях: у готовых наборов каталога
    /// в серии около 15 слов. Это мерило понятнее голого числа — «100 слов»
    /// ничего не говорит, а «≈ 7 серий» можно представить.
    public var episodesEquivalent: Int {
        Journey.episodes(forWords: threshold)
    }
}

/// Где фишка.
public struct JourneyPosition: Equatable, Sendable {
    /// Остановка, до которой уже дошли.
    public var stopIndex: Int
    /// Сколько всего слов начато.
    public var words: Int
    /// Слов после этой остановки и длина пути до следующей (0 — финиш).
    public var wordsIntoLeg: Int
    public var legLength: Int

    public var wordsToNext: Int { max(legLength - wordsIntoLeg, 0) }

    public var isFinished: Bool { legLength == 0 }

    public var fraction: Double {
        guard legLength > 0 else { return 1 }
        return min(max(Double(wordsIntoLeg) / Double(legLength), 0), 1)
    }

    public init(stopIndex: Int, words: Int, wordsIntoLeg: Int, legLength: Int) {
        self.stopIndex = stopIndex
        self.words = words
        self.wordsIntoLeg = wordsIntoLeg
        self.legLength = legLength
    }
}

/// Карта-путешествие: фишка с Мончиком идёт от остановки к остановке, как в
/// настольной игре, а остановки — это число начатых слов: 10, 25, 50, 100…
///
/// Раньше остановки были городами из сериалов, а ход — «шагами» (слово
/// начато — шаг, выучено — ещё шаг). Ни то, ни другое нельзя было проверить:
/// сколько это — «до Scranton 12 шагов»? Теперь каждая остановка — число,
/// которое видно и в статистике. Считаются начатые слова, а не выученные:
/// выученные зреют недели, и начинающий три недели стоял бы на старте.
/// Сколько из них уже выучено, карта показывает рядом. Решение P-57.
public enum Journey {

    /// Пороги остановок. Шаг растёт с числом слов: 10 → 25 в начале — та же
    /// доля пути, что 5000 → 6000 в конце, и первая же сессия сдвигает фишку.
    public static let thresholds: [Int] = [
        0, 10, 25, 50, 75, 100, 150, 200, 250, 300,
        400, 500, 600, 700, 850, 1000, 1200, 1400, 1600, 1800,
        2000, 2500, 3000, 3500, 4000, 5000, 6000, 7000, 8500, 10000,
    ]

    /// Вехи, на которых сундук и праздник: круглые числа, которые приятно
    /// назвать вслух. Праздник на каждой остановке быстро приелся бы.
    public static let chestThresholds: Set<Int> = [100, 250, 500, 1000, 2000, 3000, 5000, 7000]

    /// Слов в серии у готовых наборов каталога — для «≈ N серий».
    public static let wordsPerEpisode = 15

    public static let stops: [JourneyStop] = thresholds.enumerated().map { index, threshold in
        let kind: JourneyStop.Kind
        if index == 0 {
            kind = .start
        } else if index == thresholds.count - 1 {
            kind = .finish
        } else if chestThresholds.contains(threshold) {
            kind = .chest
        } else {
            kind = .step
        }
        return JourneyStop(index: index, threshold: threshold, kind: kind)
    }

    /// Серий, в которых примерно столько слов. Хотя бы одна — иначе
    /// «10 слов ≈ 0 серий» звучало бы как насмешка.
    public static func episodes(forWords words: Int) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int((Double(words) / Double(wordsPerEpisode)).rounded()))
    }

    /// Положение фишки. Отрицательное число слов — ноль. После финиша фишка
    /// стоит на нём: дальше 10 000 слов карта не ведёт, и это честно.
    public static func position(words rawWords: Int) -> JourneyPosition {
        let words = max(rawWords, 0)
        let index = stops.lastIndex { $0.threshold <= words } ?? 0
        let here = stops[index].threshold
        guard index + 1 < stops.count else {
            return JourneyPosition(stopIndex: index, words: words, wordsIntoLeg: 0, legLength: 0)
        }
        return JourneyPosition(stopIndex: index, words: words, wordsIntoLeg: words - here,
                               legLength: stops[index + 1].threshold - here)
    }

    /// Веха, которую стоит отпраздновать: последний сундук или финиш,
    /// пройденный с прошлого праздника, или nil.
    ///
    /// `celebrated` меньше нуля — праздновать ещё не начинали (первый запуск
    /// после обновления): иначе человек с полугодом учёбы получил бы салют
    /// за веху, пройденную давно. Откат (слова удалены) праздника не даёт,
    /// и повторного за ту же веху тоже.
    public static func stopToCelebrate(celebrated: Int, reached: Int) -> Int? {
        guard celebrated >= 0, reached > celebrated else { return nil }
        let last = min(reached, stops.count - 1)
        guard last > celebrated else { return nil }
        return ((celebrated + 1)...last).last { isMilestone(stops[$0]) }
    }

    public static func isMilestone(_ stop: JourneyStop) -> Bool {
        stop.kind == .chest || stop.kind == .finish
    }
}
