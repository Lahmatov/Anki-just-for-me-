import Foundation

/// Тест словарного запаса «знаю / не знаю» с несуществующими словами.
///
/// Устроен как тесты Миры (Meara, Yes/No vocabulary test) и LexTALE: слова
/// разной частоты вперемешку с правдоподобными выдумками. Отвечать «знаю»
/// на выдумку — значит переоценивать себя, и на эту долю поправляется
/// весь результат. Так тест честен без единого вопроса «что это значит»
/// и не зависит от языка интерфейса: переводить нечего.
///
/// Частота — по субтитрам (OpenSubtitles, списки FrequencyWords): для того,
/// кто учит язык по сериалам, это самая подходящая шкала. Шесть слов на
/// полосу частоты, шестнадцать выдумок — около трёх минут.
///
/// Оценка приблизительная, и это нормально: уровень нужен, чтобы подбирать
/// слова для наборов, и его всегда можно поправить руками.
public enum PlacementTest {

    public struct Band: Equatable, Sendable {
        /// Границы по рангу частоты, включительно.
        public var lower: Int
        public var upper: Int
        public var words: [String]

        public var width: Int { upper - lower + 1 }
    }

    public static let bands: [Band] = [
        Band(lower: 1, upper: 1_000,
             words: ["worry", "laugh", "smell", "lucky", "afraid", "proud"]),
        Band(lower: 1_001, upper: 2_000,
             words: ["bother", "afford", "rough", "bottom", "brave", "somehow"]),
        Band(lower: 2_001, upper: 4_000,
             words: ["closet", "climb", "steady", "beard", "freeze", "fence"]),
        Band(lower: 4_001, upper: 7_000,
             words: ["fierce", "hollow", "stain", "faint", "shrimp", "sweater"]),
        Band(lower: 7_001, upper: 12_000,
             words: ["vouch", "tread", "conceal", "eerie", "kettle", "squeal"]),
        Band(lower: 12_001, upper: 20_000,
             words: ["feisty", "crafty", "quaint", "solace", "smuggle", "flattery"]),
    ]

    /// Выдумки по правилам английской орфографии. Проверено, что ни одной
    /// нет среди 50 тысяч самых частых словоформ субтитров.
    public static let pseudowords = [
        "plound", "crumper", "fleeth", "brantic", "gloathe", "stroffle", "mulpish", "cradify",
        "sprounce", "tharmle", "quibbet", "hesterly", "vorbish", "drentle", "slimber", "pranch",
    ]

    /// Больше четверти «знаю» на выдумках — результат ненадёжен.
    public static let reliableFalseAlarmLimit = 0.25

    public static var maxEstimate: Int { bands.map(\.width).reduce(0, +) }

    // MARK: - Порядок

    public struct Item: Equatable, Hashable, Sendable {
        public var word: String
        /// Номер полосы частоты или nil для выдумки.
        public var band: Int?

        public var isReal: Bool { band != nil }
    }

    public static var allItems: [Item] {
        bands.enumerated().flatMap { index, band in
            band.words.map { Item(word: $0, band: index) }
        } + pseudowords.map { Item(word: $0, band: nil) }
    }

    /// Вперемешку, но воспроизводимо: одно и то же зерно даёт один порядок.
    /// Первые слова — из самой частой полосы: начинать с «feisty» и выдумок
    /// значит сразу сбить человека с толку.
    public static func items(seed: UInt64) -> [Item] {
        var generator = SplitMix64(seed: seed)
        let warmUp = Array(bands[0].words.prefix(2)).map { Item(word: $0, band: 0) }
        let rest = allItems.filter { !warmUp.contains($0) }.shuffled(using: &generator)
        return warmUp + rest
    }

    // MARK: - Оценка

    public struct Result: Equatable, Sendable {
        /// Доля «знаю» по каждой полосе, до поправки.
        public var hitRates: [Double]
        /// Доля «знаю» на выдумках.
        public var falseAlarmRate: Double
        /// Сколько слов из самых частых в субтитрах, примерно.
        public var estimatedWords: Int
        public var level: CEFRLevel
        public var isReliable: Bool
    }

    /// - Parameter answers: слово → «знаю». Пропущенные слова не учитываются.
    public static func score(_ answers: [String: Bool]) -> Result {
        let falseAlarm = rate(of: pseudowords, in: answers)
        let hitRates = bands.map { rate(of: $0.words, in: answers) }

        // Поправка на угадывание: доля «знаю» сверх той, что человек
        // говорит и на выдумки. Кто отвечает «знаю» на всё, получает ноль.
        let adjusted = hitRates.map { hit -> Double in
            guard falseAlarm < 1 else { return 0 }
            return min(1, max(0, (hit - falseAlarm) / (1 - falseAlarm)))
        }
        let estimate = zip(bands, adjusted)
            .map { Double($0.width) * $1 }
            .reduce(0, +)
        let words = Int(estimate.rounded())

        let answeredPseudo = pseudowords.contains { answers[$0] != nil }
        return Result(
            hitRates: hitRates,
            falseAlarmRate: falseAlarm,
            estimatedWords: words,
            level: level(forEstimatedWords: words),
            isReliable: answeredPseudo && falseAlarm <= reliableFalseAlarmLimit)
    }

    /// Пороги по глубине частотного списка субтитров. Опора — покрытие:
    /// 3 тысячи семейств слов закрывают около 95% текста фильмов и сериалов,
    /// 6–7 тысяч — 98%, при которых смотрят без субтитров (Webb & Rodgers,
    /// 2009). Здесь счёт идёт по словоформам, а их больше, чем семейств,
    /// поэтому границы сдвинуты вверх и округлены до полос теста.
    public static func level(forEstimatedWords words: Int) -> CEFRLevel {
        switch words {
        case ..<1_000: return .a1
        case ..<2_000: return .a2
        case ..<4_000: return .b1
        case ..<7_000: return .b2
        case ..<12_000: return .c1
        default: return .c2
        }
    }

    private static func rate(of words: [String], in answers: [String: Bool]) -> Double {
        let answered = words.compactMap { answers[$0] }
        guard !answered.isEmpty else { return 0 }
        return Double(answered.filter { $0 }.count) / Double(answered.count)
    }
}

/// Простой генератор с зерном: `SystemRandomNumberGenerator` зерна не
/// принимает, а порядок теста должен воспроизводиться в тестах.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
