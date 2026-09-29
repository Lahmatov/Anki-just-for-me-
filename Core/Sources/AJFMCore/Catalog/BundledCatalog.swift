import Foundation

/// Каталог готовых наборов, вшитый в приложение: топ-50 сериалов, первый
/// сезон, слова к каждой серии сразу на трёх языках.
///
/// Работает без сервера и без ИИ: слова собраны заранее и лежат в ресурсах
/// (исходник — backend/catalog/words, сборка — `npm run catalog -- local`).
/// Тот же исходник уходит и в базу сервера, так что наборы не расходятся.
public struct CatalogIndex: Codable, Equatable, Sendable {
    public static let formatID = "recap-catalog"

    public var format: String
    public var version: Int
    public var shows: [CatalogIndexEntry]

    public init(format: String = CatalogIndex.formatID, version: Int = 1, shows: [CatalogIndexEntry]) {
        self.format = format
        self.version = version
        self.shows = shows
    }
}

public struct CatalogIndexEntry: Codable, Equatable, Sendable, Identifiable {
    /// Имя файла ресурса без расширения: «catalog-show-01».
    public var resource: String
    public var name: String
    public var year: Int?
    public var accent: String?
    public var rank: Int
    public var episodes: Int
    public var words: Int

    public var id: String { resource }

    public init(resource: String, name: String, year: Int? = nil, accent: String? = nil,
                rank: Int, episodes: Int, words: Int) {
        self.resource = resource
        self.name = name
        self.year = year
        self.accent = accent
        self.rank = rank
        self.episodes = episodes
        self.words = words
    }
}

public struct CatalogShowFile: Codable, Equatable, Sendable {
    public var name: String
    public var year: Int?
    public var accent: String?
    public var rank: Int
    public var episodes: [CatalogEpisode]

    public init(name: String, year: Int? = nil, accent: String? = nil, rank: Int, episodes: [CatalogEpisode]) {
        self.name = name
        self.year = year
        self.accent = accent
        self.rank = rank
        self.episodes = episodes
    }
}

public struct CatalogEpisode: Codable, Equatable, Sendable, Identifiable {
    public var season: Int
    public var episode: Int
    public var title: String
    public var notes: [CatalogNote]

    public var id: String { "\(season)-\(episode)" }

    /// «S01E03».
    public var code: String { String(format: "S%02dE%02d", season, episode) }

    public init(season: Int, episode: Int, title: String, notes: [CatalogNote]) {
        self.season = season
        self.episode = episode
        self.title = title
        self.notes = notes
    }
}

/// Слово каталога: переводы и заметки — словари по коду языка («ru», «pt», «en»).
public struct CatalogNote: Codable, Equatable, Sendable {
    public var term: String
    public var ipa: String?
    public var partOfSpeech: String?
    public var translation: [String: String]
    public var example: String?
    public var exampleTranslation: [String: String]?
    public var cloze: String?
    public var note: [String: String]?

    public init(term: String, ipa: String? = nil, partOfSpeech: String? = nil,
                translation: [String: String], example: String? = nil,
                exampleTranslation: [String: String]? = nil, cloze: String? = nil,
                note: [String: String]? = nil) {
        self.term = term
        self.ipa = ipa
        self.partOfSpeech = partOfSpeech
        self.translation = translation
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.cloze = cloze
        self.note = note
    }
}

public enum BundledCatalog {
    public enum Failure: Error, Equatable {
        case foreignFormat
        case unsupportedVersion(Int)
    }

    public static func decodeIndex(_ data: Data) throws -> CatalogIndex {
        let index = try JSONDecoder().decode(CatalogIndex.self, from: data)
        guard index.format == CatalogIndex.formatID else { throw Failure.foreignFormat }
        guard index.version == 1 else { throw Failure.unsupportedVersion(index.version) }
        return index
    }

    public static func decodeShow(_ data: Data) throws -> CatalogShowFile {
        try JSONDecoder().decode(CatalogShowFile.self, from: data)
    }

    /// Слова на языке ученика. Слово без перевода на этот язык пропускается,
    /// а не заменяется английским толкованием — та же причина, что на
    /// сервере: в русском наборе английская строка выдаёт ответ на карточке
    /// «выбери перевод».
    public static func notes(_ notes: [CatalogNote], language: AppLanguage,
                             knownTerms: Set<String> = []) -> [NoteData] {
        let code = language.rawValue
        let known = Set(knownTerms.map { $0.lowercased() })
        return notes.compactMap { note in
            guard !known.contains(note.term.lowercased()),
                  let translation = clean(note.translation[code]) else { return nil }
            return NoteData(
                term: note.term,
                translation: translation,
                ipa: clean(note.ipa),
                partOfSpeech: note.partOfSpeech.flatMap(PartOfSpeech.init(rawValue:)),
                example: clean(note.example),
                // Английскому ученику перевод примера на английский не нужен.
                exampleTranslation: language == .english ? nil : clean(note.exampleTranslation?[code]),
                cloze: clean(note.cloze),
                note: clean(note.note?[code]))
        }
    }

    /// Набор к серии в формате приложения — папка та же, что у наборов с сервера.
    public static func deckFile(show: CatalogShowFile, episode: CatalogEpisode,
                                language: AppLanguage, knownTerms: Set<String> = []) -> DeckFile {
        let folder: (shows: String, season: String)
        switch language {
        case .russian: folder = ("Сериалы", "Сезон") // lint: не интерфейс
        case .portuguese: folder = ("Séries", "Temporada")
        case .english: folder = ("TV shows", "Season")
        }
        let name = episode.title.isEmpty ? episode.code : "\(episode.code) · \(episode.title)"
        return DeckFile(
            deck: DeckMeta(
                name: name,
                folder: "\(folder.shows)/\(show.name)/\(folder.season) \(episode.season)",
                source: "\(show.name) \(episode.code)"),
            notes: notes(episode.notes, language: language, knownTerms: knownTerms))
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
