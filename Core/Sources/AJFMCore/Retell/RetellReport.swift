import Foundation

/// Разбор пересказа серии — то, что возвращает модель.
///
/// Структура специально разделена на две оси: понимание содержания и качество
/// английского. Смешивать их нельзя — это разные навыки, и смешанный отзыв
/// вида «неплохо, но поработай над грамматикой» бесполезен.
public struct RetellReport: Codable, Equatable, Sendable {
    public var understanding: Understanding
    public var language: LanguageFeedback
    /// Не больше трёх — иначе после каждого пересказа получаешь стену текста
    /// и перестаёшь её читать.
    public var topPriorities: [String]

    public init(
        understanding: Understanding, language: LanguageFeedback, topPriorities: [String]
    ) {
        self.understanding = understanding
        self.language = language
        self.topPriorities = topPriorities
    }

    /// Отсутствующее поле не должно ронять разбор: запрос уже оплачен,
    /// и терять его из-за пропущенного пустого массива — самый обидный
    /// способ потратить деньги впустую.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUnderstanding = try? c.decode(Understanding.self, forKey: .understanding)
        let decodedLanguage = try? c.decode(LanguageFeedback.self, forKey: .language)

        // Терпимость к пропущенному полю — не повод принимать что угодно.
        // Ответ, обрезанный по лимиту токенов, декодировался бы в «отчёт»
        // без единой ошибки, попадал в историю и портил статистику.
        guard decodedUnderstanding != nil || decodedLanguage != nil else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: tr(
                    "в ответе нет ни разбора понимания, ни разбора языка — "
                        + "похоже, он оборвался",
                    "a resposta não traz nem a análise da compreensão nem a da língua — "
                        + "parece ter sido cortada",
                    "the reply has neither the understanding review nor the language "
                        + "review — it looks cut off")))
        }

        understanding = decodedUnderstanding
            ?? Understanding(correct: [], incorrect: [], missed: [], coverage: 0)
        language = decodedLanguage
            ?? LanguageFeedback(
                grammar: [], vocabulary: [], fluencyNote: nil, suggestedWords: [])
        topPriorities = (try? c.decode([String].self, forKey: .topPriorities)) ?? []
    }

    public struct Understanding: Codable, Equatable, Sendable {
        public var correct: [Point]
        public var incorrect: [Point]
        public var missed: [Point]
        /// Доля ключевых событий, которые ты упомянул, 0...1.
        public var coverage: Double

        public init(
            correct: [Point], incorrect: [Point], missed: [Point], coverage: Double
        ) {
            self.correct = correct
            self.incorrect = incorrect
            self.missed = missed
            self.coverage = coverage
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            correct = (try? c.decode([Point].self, forKey: .correct)) ?? []
            incorrect = (try? c.decode([Point].self, forKey: .incorrect)) ?? []
            missed = (try? c.decode([Point].self, forKey: .missed)) ?? []
            coverage = (try? c.decode(Double.self, forKey: .coverage)) ?? 0
        }

        public var coveragePercent: Int { Int((coverage * 100).rounded()) }
    }

    /// Утверждение из пересказа с цитатой из субтитров.
    public struct Point: Codable, Equatable, Sendable {
        public var claim: String
        /// Цитата из субтитров, подтверждающая или опровергающая утверждение.
        /// Без неё модель начинает сочинять — см. docs/retell.md, ловушка 1.
        public var quote: String?
        public var comment: String?
        /// Возможная ошибка распознавания, а не понимания.
        public var mayBeMisheard: Bool?

        public init(
            claim: String, quote: String? = nil, comment: String? = nil,
            mayBeMisheard: Bool? = nil
        ) {
            self.claim = claim
            self.quote = quote
            self.comment = comment
            self.mayBeMisheard = mayBeMisheard
        }
    }

    public struct LanguageFeedback: Codable, Equatable, Sendable {
        public var grammar: [Correction]
        public var vocabulary: [Correction]
        public var fluencyNote: String?
        /// Слова, которых не хватило, — прямые кандидаты в карточки.
        public var suggestedWords: [SuggestedWord]

        public init(
            grammar: [Correction], vocabulary: [Correction],
            fluencyNote: String?, suggestedWords: [SuggestedWord]
        ) {
            self.grammar = grammar
            self.vocabulary = vocabulary
            self.fluencyNote = fluencyNote
            self.suggestedWords = suggestedWords
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            grammar = (try? c.decode([Correction].self, forKey: .grammar)) ?? []
            vocabulary = (try? c.decode([Correction].self, forKey: .vocabulary)) ?? []
            fluencyNote = try? c.decode(String.self, forKey: .fluencyNote)
            suggestedWords =
                (try? c.decode([SuggestedWord].self, forKey: .suggestedWords)) ?? []
        }
    }

    public struct Correction: Codable, Equatable, Sendable {
        public var said: String
        public var better: String
        public var why: String?

        public init(said: String, better: String, why: String? = nil) {
            self.said = said
            self.better = better
            self.why = why
        }
    }

    public struct SuggestedWord: Codable, Equatable, Sendable {
        public var term: String
        public var translation: String
        public var example: String?
        /// Что ты сказал вместо этого слова.
        public var insteadOf: String?

        public init(
            term: String, translation: String, example: String? = nil, insteadOf: String? = nil
        ) {
            self.term = term
            self.translation = translation
            self.example = example
            self.insteadOf = insteadOf
        }
    }
}

extension RetellReport {
    /// Превращает разбор в набор карточек.
    ///
    /// Это замыкает главный контур приложения: посмотрел → пересказал →
    /// ошибки стали карточками → выучил → следующий пересказ лучше.
    public func makeDeck(name: String, folder: String? = nil) -> DeckFile? {
        var notes: [NoteData] = []

        for word in language.suggestedWords {
            let hint = word.insteadOf.map {
                tr("Ты сказал «\($0)».", "Disseste «\($0)».", "You said “\($0)”.")
            }
            notes.append(NoteData(
                term: word.term,
                translation: word.translation,
                example: word.example,
                note: hint,
                tags: [tr("пересказ", "reconto", "retelling"),
                       tr("словарь", "vocabulário", "vocabulary")]))
        }

        for correction in language.grammar {
            notes.append(NoteData(
                term: correction.better,
                translation: correction.why
                    ?? tr("Правильная форма", "Forma correta", "Correct form"),
                example: correction.better,
                note: tr("Было: «\(correction.said)»",
                         "Antes: «\(correction.said)»",
                         "You said: “\(correction.said)”"),
                tags: [tr("пересказ", "reconto", "retelling"),
                       tr("грамматика", "gramática", "grammar")]))
        }

        guard !notes.isEmpty else { return nil }

        return DeckFile(
            deck: DeckMeta(
                name: name,
                folder: folder,
                language: "en-US",
                scheduler: .fsrs6,
                cardTypes: [.recognition, .recall],
                source: tr("разбор пересказа", "análise do reconto", "retelling review")),
            notes: notes)
    }

    /// Короткая сводка для списка пересказов.
    public var summaryLine: String {
        let coverage = understanding.coveragePercent
        let mistakes = language.grammar.count + language.vocabulary.count
        return tr("Понимание \(coverage)% · замечаний по языку: \(mistakes)",
                  "Compreensão \(coverage)% · observações de língua: \(mistakes)",
                  "Understanding \(coverage)% · language notes: \(mistakes)")
    }
}
