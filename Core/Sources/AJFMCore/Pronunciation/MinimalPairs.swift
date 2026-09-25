import Foundation

/// Пара слов, различающихся одним звуком.
public struct MinimalPair: Equatable, Sendable, Identifiable {
    public var first: String
    public var second: String
    /// Какие звуки противопоставляются.
    public var contrast: String
    /// Как их различать на практике — для каждого родного языка своё:
    /// подсказка опирается на звуки, которые ученик уже умеет произносить.
    private var hints: [AppLanguage: String]

    public var id: String { "\(first)-\(second)" }

    public init(
        _ first: String, _ second: String, contrast: String,
        ru: String, pt: String, en: String
    ) {
        self.first = first
        self.second = second
        self.contrast = contrast
        self.hints = [.russian: ru, .portuguese: pt, .english: en]
    }

    public var hint: String { hints[Loc.language] ?? hints[.english] ?? "" }

    public var words: [String] { [first, second] }

    public func other(than word: String) -> String {
        TermNormalizer.normalize(word) == TermNormalizer.normalize(first) ? second : first
    }
}

/// Минимальные пары под типичные трудности тех, для кого английский не родной.
///
/// Зачем это нужно: обычное распознавание речи почти бесполезно как проверка
/// произношения — оно подгоняет услышанное под словарь. А вот когда два слова
/// различаются ровно одним звуком, выбор распознавателя становится честным
/// сигналом: услышал «sheep» вместо «ship» — значит гласная действительно
/// прозвучала длинной.
///
/// Трудные пары у русско- и португалоязычных почти совпадают: в обоих языках
/// нет /ɪ/, /æ/, /ʌ/, /θ/ и /ð/. Разнятся подсказки — они ссылаются на звуки
/// родного языка.
public enum MinimalPairLibrary {

    public static let all: [MinimalPair] = [
        MinimalPair(
            "ship", "sheep", contrast: "/ɪ/ — /iː/",
            ru: "В русском нет короткой /ɪ/: она не «и», а расслабленный звук между «и» и «ы».",
            pt: "Em português não há /ɪ/ curto: não é «i», é um som relaxado entre «i» e «ê».",
            en: "The short /ɪ/ isn't “ee”: it's a relaxed sound between “ee” and “eh”."),
        MinimalPair(
            "fill", "feel", contrast: "/ɪ/ — /iː/",
            ru: "Долгота не главное — важно само качество гласной.",
            pt: "A duração não é o principal — conta a qualidade da vogal.",
            en: "Length isn't the main thing — the quality of the vowel is."),
        MinimalPair(
            "live", "leave", contrast: "/ɪ/ — /iː/",
            ru: "«Жить» короче и расслабленнее, чем «уезжать».",
            pt: "«Viver» é mais curto e relaxado do que «partir».",
            en: "“Live” is shorter and more relaxed than “leave”."),
        MinimalPair(
            "bad", "bed", contrast: "/æ/ — /e/",
            ru: "/æ/ — рот шире, челюсть ниже, звук ближе к «а».",
            pt: "/æ/ — boca mais aberta, maxilar mais baixo, som mais próximo de «á».",
            en: "/æ/ — mouth wider, jaw lower, closer to “ah”."),
        MinimalPair(
            "man", "men", contrast: "/æ/ — /e/",
            ru: "Во множественном числе рот уже, звук ближе к «э».",
            pt: "No plural a boca fecha-se mais, o som aproxima-se de «é».",
            en: "In the plural the mouth is narrower, closer to “eh”."),
        MinimalPair(
            "bag", "beg", contrast: "/æ/ — /e/",
            ru: "Русское «э» почти всегда звучит как /e/ — для /æ/ рот надо раскрыть.",
            pt: "O «é» português soa quase sempre a /e/ — para /æ/ abre mais a boca.",
            en: "A plain “e” comes out as /e/ — for /æ/ open your mouth wider."),
        MinimalPair(
            "thin", "sin", contrast: "/θ/ — /s/",
            ru: "Кончик языка между зубами. Свист вместо этого выдаёт русский акцент.",
            pt: "Ponta da língua entre os dentes. Um «s» no lugar denuncia o sotaque.",
            en: "Tip of the tongue between the teeth. An “s” instead gives the accent away."),
        MinimalPair(
            "three", "tree", contrast: "/θ/ — /t/",
            ru: "Не «т» и не «с» — воздух проходит между языком и зубами.",
            pt: "Nem «t» nem «s» — o ar passa entre a língua e os dentes.",
            en: "Not “t” and not “s” — the air passes between tongue and teeth."),
        MinimalPair(
            "they", "day", contrast: "/ð/ — /d/",
            ru: "Звонкий межзубный: язык там же, где в «thin», но с голосом.",
            pt: "Interdental sonoro: a língua no mesmo sítio que em «thin», mas com voz.",
            en: "The voiced one: tongue where it is in “thin”, but with voice."),
        MinimalPair(
            "vest", "west", contrast: "/v/ — /w/",
            ru: "/w/ — губы трубочкой, зубы не касаются губы. Русское «в» — всегда /v/.",
            pt: "/w/ — lábios arredondados, os dentes não tocam no lábio, como o «u» de «quase».",
            en: "/w/ — rounded lips, the teeth don't touch the lip."),
        MinimalPair(
            "wine", "vine", contrast: "/w/ — /v/",
            ru: "Если нижняя губа коснулась зубов — вышло /v/.",
            pt: "Se o lábio inferior tocou nos dentes, saiu /v/.",
            en: "If your lower lip touched your teeth, it came out as /v/."),
        MinimalPair(
            "full", "fool", contrast: "/ʊ/ — /uː/",
            ru: "Короткая /ʊ/ расслаблена, губы почти не вытянуты.",
            pt: "O /ʊ/ curto é relaxado, os lábios quase não avançam.",
            en: "Short /ʊ/ is relaxed, the lips barely push forward."),
        MinimalPair(
            "pull", "pool", contrast: "/ʊ/ — /uː/",
            ru: "То же различие, что в ship/sheep, только для «у».",
            pt: "A mesma diferença que em ship/sheep, mas para o «u».",
            en: "The same difference as in ship/sheep, but for “oo”."),
        MinimalPair(
            "cat", "cut", contrast: "/æ/ — /ʌ/",
            ru: "/ʌ/ — короткий безударный звук, ближе к русскому «а» в «пока».",
            pt: "/ʌ/ — som curto e neutro, parecido com o «a» átono de «cama».",
            en: "/ʌ/ — a short, relaxed “uh”."),
        MinimalPair(
            "hat", "hut", contrast: "/æ/ — /ʌ/",
            ru: "Для /æ/ рот шире и звук тянется дольше.",
            pt: "Para /æ/ a boca abre mais e o som dura mais.",
            en: "For /æ/ the mouth opens wider and the sound lasts longer."),
        MinimalPair(
            "work", "walk", contrast: "/ɜːr/ — /ɔː/",
            ru: "В «work» есть американская /r/, в «walk» — «л» не произносится вовсе.",
            pt: "Em «work» há o /r/ americano; em «walk» o «l» nem se pronuncia.",
            en: "“Work” has the American /r/; in “walk” the “l” is silent."),
        MinimalPair(
            "sink", "think", contrast: "/s/ — /θ/",
            ru: "Классическая ловушка: «я думаю» легко превращается в «я тону».",
            pt: "Armadilha clássica: «eu penso» transforma-se facilmente em «eu afundo».",
            en: "The classic trap: “I think” easily turns into “I sink”."),
        MinimalPair(
            "cheap", "chip", contrast: "/iː/ — /ɪ/",
            ru: "Дешёвый — длинный звук, чипс — короткий.",
            pt: "«Barato» tem o som longo, «batata frita» o curto.",
            en: "Cheap has the long sound, chip the short one."),
    ]

    public static func pair(containing word: String) -> MinimalPair? {
        let target = TermNormalizer.normalize(word)
        return all.first {
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
                message: tr("Различие \(pair.contrast) услышано верно.",
                            "A diferença \(pair.contrast) ouviu-se bem.",
                            "The \(pair.contrast) difference came through clearly."),
                isReliable: true)
        }

        if heard == opposite {
            return PronunciationAssessment(
                verdict: .mismatched, recognized: recognized, expected: target,
                confidence: confidence, alternatives: [],
                message: tr(
                    "Прозвучало «\(recognized)» вместо «\(target)». Это ровно то различие, "
                        + "над которым стоит поработать: \(pair.contrast). \(pair.hint)",
                    "Ouviu-se «\(recognized)» em vez de «\(target)». É exatamente a diferença "
                        + "a trabalhar: \(pair.contrast). \(pair.hint)",
                    "It sounded like “\(recognized)” instead of “\(target)”. That's exactly "
                        + "the difference to work on: \(pair.contrast). \(pair.hint)"),
                isReliable: true)
        }

        return PronunciationAssessment(
            verdict: .unclear, recognized: recognized, expected: target,
            confidence: confidence, alternatives: [],
            message: recognized.isEmpty
                ? tr("Ничего не разобрал — попробуй ещё раз.",
                     "Não percebi nada — tenta outra vez.",
                     "Couldn't make anything out — try again.")
                : tr("Услышал «\(recognized)» — ни одно из слов пары. "
                        + "Скорее всего, дело в записи.",
                     "Ouvi «\(recognized)» — nenhuma das palavras do par. "
                        + "Provavelmente é da gravação.",
                     "Heard “\(recognized)” — neither word of the pair. "
                        + "Most likely it's the recording."),
            isReliable: false)
    }
}
