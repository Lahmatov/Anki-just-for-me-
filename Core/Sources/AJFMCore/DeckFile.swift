import Foundation

/// Формат файла набора карточек (`ajfm-deck`).
/// Спецификация — docs/deck-format.md, схема — schema/deck.schema.json.
public struct DeckFile: Codable, Equatable, Sendable {
    public static let formatID = "ajfm-deck"
    public static let supportedVersion = 1

    public var format: String
    public var version: Int
    public var deck: DeckMeta
    public var notes: [NoteData]

    public init(deck: DeckMeta, notes: [NoteData]) {
        self.format = Self.formatID
        self.version = Self.supportedVersion
        self.deck = deck
        self.notes = notes
    }
}

public struct DeckMeta: Codable, Equatable, Sendable {
    public var name: String
    public var folder: String?
    public var language: String?
    public var scheduler: SchedulerID?
    public var cardTypes: [CardType]?
    public var source: String?

    public init(
        name: String,
        folder: String? = nil,
        language: String? = nil,
        scheduler: SchedulerID? = nil,
        cardTypes: [CardType]? = nil,
        source: String? = nil
    ) {
        self.name = name
        self.folder = folder
        self.language = language
        self.scheduler = scheduler
        self.cardTypes = cardTypes
        self.source = source
    }

    // Мягкое декодирование: неизвестный алгоритм или тип карточки не должен
    // ронять весь импорт — такие значения отбрасываются, а ImportPlan
    // сообщит об этом предупреждением.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        scheduler = c.decodeLenient(SchedulerID.self, forKey: .scheduler)
        let rawTypes = try? c.decodeIfPresent([String].self, forKey: .cardTypes)
        cardTypes = (rawTypes ?? nil).map { $0.compactMap(CardType.init(rawValue:)) }
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

public struct NoteData: Codable, Equatable, Sendable {
    public var term: String
    public var translation: String
    public var ipa: String?
    public var partOfSpeech: PartOfSpeech?
    public var example: String?
    public var exampleTranslation: String?
    public var cloze: String?
    public var synonyms: [String]?
    public var note: String?
    public var tags: [String]?
    public var difficulty: Difficulty?
    public var audio: String?

    public init(
        term: String,
        translation: String,
        ipa: String? = nil,
        partOfSpeech: PartOfSpeech? = nil,
        example: String? = nil,
        exampleTranslation: String? = nil,
        cloze: String? = nil,
        synonyms: [String]? = nil,
        note: String? = nil,
        tags: [String]? = nil,
        difficulty: Difficulty? = nil,
        audio: String? = nil
    ) {
        self.term = term
        self.translation = translation
        self.ipa = ipa
        self.partOfSpeech = partOfSpeech
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.cloze = cloze
        self.synonyms = synonyms
        self.note = note
        self.tags = tags
        self.difficulty = difficulty
        self.audio = audio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        translation = try c.decode(String.self, forKey: .translation)
        ipa = try c.decodeIfPresent(String.self, forKey: .ipa)
        partOfSpeech = c.decodeLenient(PartOfSpeech.self, forKey: .partOfSpeech)
        example = try c.decodeIfPresent(String.self, forKey: .example)
        exampleTranslation = try c.decodeIfPresent(String.self, forKey: .exampleTranslation)
        cloze = try c.decodeIfPresent(String.self, forKey: .cloze)
        synonyms = try c.decodeIfPresent([String].self, forKey: .synonyms)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        difficulty = c.decodeLenient(Difficulty.self, forKey: .difficulty)
        audio = try c.decodeIfPresent(String.self, forKey: .audio)
    }
}

public enum SchedulerID: String, Codable, CaseIterable, Sendable {
    case fsrs6, sm2, leitner, cram

    public var title: String {
        switch self {
        case .fsrs6: return "FSRS-6"
        case .sm2: return "SM-2"
        case .leitner: return "Лейтнер"
        case .cram: return "Зубрёжка"
        }
    }
}

public enum CardType: String, Codable, CaseIterable, Sendable {
    case recognition, recall, listening, spelling, pronunciation, cloze

    public var title: String {
        switch self {
        case .recognition: return "Узнавание"
        case .recall: return "Воспроизведение"
        case .listening: return "На слух"
        case .spelling: return "Написание"
        case .pronunciation: return "Произношение"
        case .cloze: return "Пропуск"
        }
    }
}

public enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun, verb, adjective, adverb
    case phrasalVerb = "phrasal verb"
    case idiom, phrase, other
}

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard
}

extension KeyedDecodingContainer {
    /// Неизвестное значение перечисления не роняет импорт — поле просто становится nil.
    func decodeLenient<T: RawRepresentable>(_ type: T.Type, forKey key: Key) -> T?
    where T.RawValue == String {
        // try? уже даёт String? — Swift не добавляет второй уровень опциональности.
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return raw.flatMap(T.init(rawValue:))
    }
}
