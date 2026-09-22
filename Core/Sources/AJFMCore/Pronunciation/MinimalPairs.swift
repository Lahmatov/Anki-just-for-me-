import Foundation

/// Пара слов, различающихся одним звуком.
public struct MinimalPair: Equatable, Sendable, Identifiable {
    public var first: String
    public var second: String
    /// Какие звуки противопоставляются.
    public var contrast: String
    /// Как их различать на практике.
    public var hint: String

    public var id: String { "\(first)-\(second)" }

    public init(_ first: String, _ second: String, contrast: String, hint: String) {
        self.first = first
        self.second = second
        self.contrast = contrast
        self.hint = hint
    }

    public var words: [String] { [first, second] }

    public func other(than word: String) -> String {
        TermNormalizer.normalize(word) == TermNormalizer.normalize(first) ? second : first
    }
}

/// Минимальные пары под типичные трудности русскоязычных.
///
/// Зачем это нужно: обычное распознавание речи почти бесполезно как проверка
/// произношения — оно подгоняет услышанное под словарь. А вот когда два слова
/// различаются ровно одним звуком, выбор распознавателя становится честным
/// сигналом: услышал «sheep» вместо «ship» — значит гласная действительно
/// прозвучала длинной.
public enum MinimalPairLibrary {

    public static let forRussianSpeakers: [MinimalPair] = [
        MinimalPair(
            "ship", "sheep", contrast: "/ɪ/ против /iː/",
            hint: "В русском нет короткой /ɪ/: она не «и», а расслабленный звук между «и» и «ы»."),
        MinimalPair(
            "fill", "feel", contrast: "/ɪ/ против /iː/",
            hint: "Долгота не главное — важно само качество гласной."),
        MinimalPair(
            "live", "leave", contrast: "/ɪ/ против /iː/",
            hint: "«Жить» короче и расслабленнее, чем «уезжать»."),
        MinimalPair(
            "bad", "bed", contrast: "/æ/ против /e/",
            hint: "/æ/ — рот шире, челюсть ниже, звук ближе к «а»."),
        MinimalPair(
            "man", "men", contrast: "/æ/ против /e/",
            hint: "Во множественном числе рот уже, звук ближе к «э»."),
        MinimalPair(
            "bag", "beg", contrast: "/æ/ против /e/",
            hint: "Русское «э» почти всегда звучит как /e/ — для /æ/ рот надо раскрыть."),
        MinimalPair(
            "thin", "sin", contrast: "/θ/ против /s/",
            hint: "Кончик языка между зубами. Свист вместо этого выдаёт русский акцент."),
        MinimalPair(
            "three", "tree", contrast: "/θ/ против /t/",
            hint: "Не «т» и не «с» — воздух проходит между языком и зубами."),
        MinimalPair(
            "they", "day", contrast: "/ð/ против /d/",
            hint: "Звонкий межзубный: язык там же, где в «thin», но с голосом."),
        MinimalPair(
            "vest", "west", contrast: "/v/ против /w/",
            hint: "/w/ — губы трубочкой, зубы не касаются губы. Русское «в» — всегда /v/."),
        MinimalPair(
            "wine", "vine", contrast: "/w/ против /v/",
            hint: "Если нижняя губа коснулась зубов — вышло /v/."),
        MinimalPair(
            "full", "fool", contrast: "/ʊ/ против /uː/",
            hint: "Короткая /ʊ/ расслаблена, губы почти не вытянуты."),
        MinimalPair(
            "pull", "pool", contrast: "/ʊ/ против /uː/",
            hint: "То же различие, что в ship/sheep, только для «у»."),
        MinimalPair(
            "cat", "cut", contrast: "/æ/ против /ʌ/",
            hint: "/ʌ/ — короткий безударный звук, ближе к русскому «а» в «пока»."),
        MinimalPair(
            "hat", "hut", contrast: "/æ/ против /ʌ/",
            hint: "Для /æ/ рот шире и звук тянется дольше."),
        MinimalPair(
            "work", "walk", contrast: "/ɜːr/ против /ɔː/",
            hint: "В «work» есть американская /r/, в «walk» — «л» не произносится вовсе."),
        MinimalPair(
            "sink", "think", contrast: "/s/ против /θ/",
            hint: "Классическая ловушка: «я думаю» легко превращается в «я тону»."),
        MinimalPair(
            "cheap", "chip", contrast: "/iː/ против /ɪ/",
            hint: "Дешёвый — длинный звук, чипс — короткий."),
    ]

    public static func pair(containing word: String) -> MinimalPair? {
        let target = TermNormalizer.normalize(word)
        return forRussianSpeakers.first {
            TermNormalizer.normalize($0.first) == target
                || TermNormalizer.normalize($0.second) == target
        }
    }

    /// Оценка попытки произнести одно слово из пары.
    ///
    /// Именно здесь проверка произношения становится честной: распознаватель
    /// выбирает между двумя словами, которые различаются ровно одним звуком,
    /// и его выбор говорит о том, как этот звук прозвучал.
    public static func evaluate(
        pair: MinimalPair, target: String, recognized: String, confidence: Double
    ) -> PronunciationAssessment {
        let heard = TermNormalizer.normalize(recognized)
        let wanted = TermNormalizer.normalize(target)
        let opposite = TermNormalizer.normalize(pair.other(than: target))

        if heard == wanted {
            return PronunciationAssessment(
                verdict: .matched, recognized: recognized, expected: target,
                confidence: confidence, alternatives: [],
                message: "Различие \(pair.contrast) услышано верно.",
                isReliable: true)
        }

        if heard == opposite {
            return PronunciationAssessment(
                verdict: .mismatched, recognized: recognized, expected: target,
                confidence: confidence, alternatives: [],
                message: "Прозвучало «\(recognized)» вместо «\(target)». "
                    + "Это ровно то различие, над которым стоит поработать: "
                    + "\(pair.contrast). \(pair.hint)",
                isReliable: true)
        }

        return PronunciationAssessment(
            verdict: .unclear, recognized: recognized, expected: target,
            confidence: confidence, alternatives: [],
            message: recognized.isEmpty
                ? "Ничего не разобрал — попробуй ещё раз."
                : "Услышал «\(recognized)» — ни одно из слов пары. "
                    + "Скорее всего, дело в записи.",
            isReliable: false)
    }
}
