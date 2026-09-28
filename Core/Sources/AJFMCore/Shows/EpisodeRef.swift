import Foundation

/// Серия сериала: название, сезон, номер.
///
/// Нужна, чтобы набор по «Friends 1x03» сам лёг в папку
/// «Сериалы / Friends / Сезон 1» под именем «S01E03 · The One with the Thumb»,
/// а не в общую кучу «Claude» под тем, что человек напечатал.
public struct EpisodeRef: Equatable, Hashable, Sendable {
    public var show: String
    public var season: Int
    public var episode: Int

    public init(show: String, season: Int, episode: Int) {
        self.show = show
        self.season = season
        self.episode = episode
    }

    /// Проверенная серия или nil: без названия и с нулевыми номерами
    /// это не серия, а мусор из ответа модели.
    public init?(validatingShow show: String, season: Int, episode: Int) {
        let show = show.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !show.isEmpty, (1...99).contains(season), (1...999).contains(episode) else {
            return nil
        }
        self.init(show: show, season: season, episode: episode)
    }

    /// «S01E03» — как серии подписывают везде.
    public var code: String {
        "S" + Self.pad(season) + "E" + Self.pad(episode)
    }

    private static func pad(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }

    /// «Сериалы / Friends / Сезон 1».
    public var folderPath: [String] {
        [tr("Сериалы", "Séries", "TV shows"), show,
         tr("Сезон \(season)", "Temporada \(season)", "Season \(season)")]
    }

    public var folder: String { folderPath.joined(separator: "/") }

    /// «S01E03 · The One with the Thumb», а без названия серии — «S01E03».
    public func deckName(title: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? code : "\(code) · \(title)"
    }

    // MARK: - Разбор запроса

    /// Серия из того, что человек напечатал: «Friends 1x03», «Friends S01E03»,
    /// «friends s1 e3», «Friends season 1 episode 3», «Друзья 1 сезон 3 серия»,
    /// «Друзья сезон 1 серия 3», «Friends temporada 1 episódio 3».
    /// Разбирается на телефоне — бесплатно и сразу, без модели.
    public static func parse(_ text: String) -> EpisodeRef? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = #"[\s,.:;\-–—]*"#
        // (шаблон, номер группы сезона, номер группы серии)
        let patterns: [(String, Int, Int)] = [
            (#"^(.+?)"# + separator + #"s(\d{1,2})\s*e(\d{1,3})\b"#, 2, 3),
            (#"^(.+?)"# + separator + #"(\d{1,2})\s*x\s*(\d{1,3})\b"#, 2, 3),
            (#"^(.+?)"# + separator + #"season\s*(\d{1,2})"# + separator + #"(?:episode|ep)\s*(\d{1,3})\b"#, 2, 3),
            (#"^(.+?)"# + separator + #"temporada\s*(\d{1,2})"# + separator + #"epis[oó]dio\s*(\d{1,3})\b"#, 2, 3),
            (#"^(.+?)"# + separator + #"сезон\s*(\d{1,2})"# + separator  // lint: не интерфейс
                + #"(?:серия|эпизод)\s*(\d{1,3})"#, 2, 3),  // lint: не интерфейс
            (#"^(.+?)"# + separator + #"(\d{1,2})\s*сезон"# + separator  // lint: не интерфейс
                + #"(\d{1,3})\s*(?:серия|эпизод)"#, 2, 3),  // lint: не интерфейс
        ]
        for (pattern, seasonGroup, episodeGroup) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(
                    in: text, range: NSRange(text.startIndex..., in: text)),
                  let showRange = Range(match.range(at: 1), in: text),
                  let seasonRange = Range(match.range(at: seasonGroup), in: text),
                  let episodeRange = Range(match.range(at: episodeGroup), in: text),
                  let season = Int(text[seasonRange]),
                  let episode = Int(text[episodeRange]) else { continue }
            let show = text[showRange].trimmingCharacters(
                in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.:;-–—")))
            if let ref = EpisodeRef(validatingShow: show, season: season, episode: episode) {
                return ref
            }
        }
        return nil
    }
}
