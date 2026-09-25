import Foundation

public enum DeckRequestError: Error, Equatable, LocalizedError {
    case emptyTopic
    case subtitlesTooLong(characters: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyTopic:
            return "Напиши, по какой серии или теме нужен набор."
        case .subtitlesTooLong(let characters, let limit):
            return "Субтитры слишком длинные: \(characters) символов при пределе \(limit). "
                + "Похоже, это не одна серия, а сезон целиком."
        }
    }
}

/// Запрос «сделай набор» прямо из приложения.
///
/// Человек пишет коротко — «Friends 1x03» или «слова для собеседования
/// в IT», — модель возвращает слова по жёсткой схеме, и они попадают
/// в обычное превью импорта. Без копирования запроса в чат и файла обратно.
///
/// Главный риск — выдуманные цитаты. Без субтитров модель «вспоминает»
/// реплики, которых в серии не было, и выдаёт их за настоящие. Поэтому:
/// с субтитрами примеры берутся только из них, без субтитров — пишутся
/// как обычные примеры и цитатами не притворяются.
public struct DeckRequest: Equatable, Sendable {
    public var topic: String
    public var subtitles: String?
    public var wordCount: Int
    public var level: CEFRLevel?
    public var language: AppLanguage
    /// Слова, которые уже есть в базе, — чтобы модель не тратила на них место.
    public var knownTerms: [String]

    public static let wordCountRange = 5...40
    public static let defaultWordCount = 20
    /// Серия — это 30–60 тысяч символов. Больше — почти наверняка файл
    /// с целым сезоном, и платить за него впустую незачем.
    public static let subtitlesLimit = 200_000
    /// Сколько известных слов перечислять. Список нужен, чтобы не дублировать
    /// свежие слова; тысячи старых только удорожают запрос.
    public static let knownTermsLimit = 400
    public static let folder = "Claude"

    public init(
        topic: String, subtitles: String? = nil, wordCount: Int = DeckRequest.defaultWordCount,
        level: CEFRLevel? = nil, language: AppLanguage, knownTerms: [String] = []
    ) {
        self.topic = topic
        self.subtitles = subtitles
        self.wordCount = wordCount
        self.level = level
        self.language = language
        self.knownTerms = knownTerms
    }

    /// Проверка до отправки: ошибку лучше показать бесплатно.
    public func validate() throws {
        guard !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(subtitles ?? "").isEmpty else {
            throw DeckRequestError.emptyTopic
        }
        if let subtitles, subtitles.count > Self.subtitlesLimit {
            throw DeckRequestError.subtitlesTooLong(
                characters: subtitles.count, limit: Self.subtitlesLimit)
        }
    }

    private var clampedCount: Int {
        min(max(wordCount, Self.wordCountRange.lowerBound), Self.wordCountRange.upperBound)
    }

    private var hasSubtitles: Bool {
        !(subtitles ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Запрос

    public var system: String {
        let translationRule = language.translatesIntoItself
            ? "translation: a short, plain-English definition a learner would understand " +
              "(not a synonym list)."
            : "translation: 1–3 short equivalents in \(language.promptName), " +
              "the most common first; no explanations."

        let levelRule: String
        if let level {
            levelRule = "The learner's level is about \(level.rawValue). Pick words around " +
                "\(level.next.rawValue): new enough to be worth learning, common enough " +
                "to meet again. Skip words any \(level.rawValue) learner already knows."
        } else {
            levelRule = "The learner is intermediate (about B1–B2). Pick words that are " +
                "new at that level but common enough to meet again."
        }

        let exampleRule = hasSubtitles
            ? "example: an exact line from the attached subtitles that contains the term. " +
              "Never invent or paraphrase lines."
            : "example: a natural sentence in the style of the topic. You have no " +
              "subtitles, so do not claim it is a quote from the episode."

        return """
        You build vocabulary flashcard decks for one adult learner of American English.

        \(levelRule)
        Prefer what actually makes speech sound natural: phrasal verbs, idioms, \
        collocations and colloquial American expressions. Avoid proper names, \
        rare slang and words that only matter for this one plot.

        Rules for every entry:
        - term: the dictionary form (infinitive without "to"); keep phrasal verbs whole.
        - \(translationRule)
        - ipa: General American transcription between slashes.
        - partOfSpeech: one of the allowed values.
        - \(exampleRule)
        - exampleTranslation: the example translated into \(language.promptName).
        - cloze: the example with the term replaced by ___ (every inflected form, \
        and each part of a separated phrasal verb).
        - note: in \(language.promptName), only when there is a real pitfall — a false \
        friend, a separable phrasal verb, a British/American difference. Otherwise "".

        name: a short deck title, e.g. "Friends S01E03" or "Job interview"; \
        write it in the learner's words, not a description.
        """
    }

    public var userMessage: String {
        var parts: [String] = []
        let topic = self.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append("Make a deck of \(clampedCount) entries.")
        if !topic.isEmpty {
            parts.append("Request: \(topic)")
        }
        if !knownTerms.isEmpty {
            let list = knownTerms.prefix(Self.knownTermsLimit).joined(separator: ", ")
            parts.append("The learner already has these, skip them: \(list)")
        }
        if hasSubtitles, let subtitles {
            parts.append("<subtitles>\n\(subtitles)\n</subtitles>")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Схема ответа

    /// JSON Schema для structured outputs: ответ гарантированно разбирается,
    /// и строгая проверка формата на этом пути никогда не срабатывает зря.
    public static let outputSchemaJSON = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "notes"],
      "properties": {
        "name": { "type": "string" },
        "notes": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["term", "translation", "ipa", "partOfSpeech", "example",
                         "exampleTranslation", "cloze", "note"],
            "properties": {
              "term": { "type": "string" },
              "translation": { "type": "string" },
              "ipa": { "type": "string" },
              "partOfSpeech": {
                "type": "string",
                "enum": ["noun", "verb", "adjective", "adverb", "phrasal verb",
                         "idiom", "phrase", "other"]
              },
              "example": { "type": "string" },
              "exampleTranslation": { "type": "string" },
              "cloze": { "type": "string" },
              "note": { "type": "string" }
            }
          }
        }
      }
    }
    """

    // MARK: - Стоимость

    public var estimatedInputTokens: Int {
        RetellPrompt.estimateTokens(system) + RetellPrompt.estimateTokens(userMessage)
    }

    /// Около 110 токенов на слово с примером и переводом плюс рассуждение.
    public var estimatedOutputTokens: Int { clampedCount * 110 + 1_500 }

    /// Потолок ответа. Упереться в него значит получить обрезанный JSON,
    /// поэтому запас щедрый: платится только реально сгенерированное.
    public static let maxTokens = 16_000

    // MARK: - Ответ

    /// Набор из ответа модели. Пустые необязательные поля превращаются в nil
    /// нормализатором, папка и источник проставляются здесь.
    public func deckFile(fromResponse text: String) throws -> DeckFile {
        var file = try DeckParser.parse(string: text)
        let topic = self.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if file.deck.name == DeckNormalizer.fallbackDeckName, !topic.isEmpty {
            file.deck.name = String(topic.prefix(60))
        }
        file.deck.folder = file.deck.folder ?? Self.folder
        file.deck.source = file.deck.source ?? (topic.isEmpty ? nil : topic)
        return file
    }
}
