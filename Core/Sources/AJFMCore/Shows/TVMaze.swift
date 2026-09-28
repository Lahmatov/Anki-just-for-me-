import Foundation

/// TVMaze — бесплатная открытая база сериалов, без ключа.
///
/// Отсюда постер для набора и настоящее название серии. Запросы только
/// читают и несут одно название сериала; при любой ошибке набор просто
/// остаётся без картинки — ради неё не стоит ронять импорт.
public enum TVMaze {
    public static let host = "https://api.tvmaze.com"

    public struct Show: Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var posterURL: String?
        /// Год премьеры — чтобы отличить ремейк от оригинала в поиске.
        public var premieredYear: Int?

        public init(id: Int, name: String, posterURL: String? = nil, premieredYear: Int? = nil) {
            self.id = id
            self.name = name
            self.posterURL = posterURL
            self.premieredYear = premieredYear
        }
    }

    /// Поиск одного, самого подходящего сериала по названию.
    public static func showSearchURL(_ show: String) -> URL? {
        let trimmed = show.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: host + "/singlesearch/shows")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    public static func episodeURL(showID: Int, season: Int, episode: Int) -> URL? {
        var components = URLComponents(string: host + "/shows/\(showID)/episodebynumber")
        components?.queryItems = [
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "number", value: String(episode)),
        ]
        return components?.url
    }

    /// Сериал из ответа поиска. Постер — средний (210×295): для обложки
    /// в списке большего не нужно, а трафик меньше в разы. Адрес
    /// приводится к https — у старых записей бывает http.
    public static func parseShow(_ data: Data) -> Show? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return show(from: object)
    }

    static func show(from object: [String: Any]) -> Show? {
        guard let id = object["id"] as? Int,
              let name = object["name"] as? String, !name.isEmpty else { return nil }
        let images = object["image"] as? [String: Any]
        let poster = (images?["medium"] as? String) ?? (images?["original"] as? String)
        let year = (object["premiered"] as? String).flatMap { Int($0.prefix(4)) }
        return Show(id: id, name: name, posterURL: poster.map(secure), premieredYear: year)
    }

    // MARK: - Поиск и список серий

    /// Поиск с несколькими результатами — для выбора сериала руками.
    public static func searchURL(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: host + "/search/shows")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    /// Результаты поиска в порядке TVMaze (самые похожие первыми).
    /// Битые записи пропускаются, а не роняют весь список.
    public static func parseSearch(_ data: Data) -> [Show] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var seen = Set<Int>()
        return items.compactMap { ($0["show"] as? [String: Any]).flatMap(show(from:)) }
            .filter { seen.insert($0.id).inserted }
    }

    public static func episodesURL(showID: Int) -> URL? {
        URL(string: host + "/shows/\(showID)/episodes")
    }

    /// Серии по порядку. Спецвыпуски без номера и «нулевой сезон»
    /// пропускаются: отмечать их просмотренными и пересказывать незачем,
    /// а в прогрессе они только путают.
    public static func parseEpisodes(_ data: Data) -> [EpisodeInfo] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var seen = Set<EpisodeKey>()
        let parsed = items.compactMap { item -> EpisodeInfo? in
            guard let id = item["id"] as? Int,
                  let season = item["season"] as? Int, season >= 1,
                  let number = item["number"] as? Int, number >= 1 else { return nil }
            let name = (item["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return EpisodeInfo(
                id: id, season: season, number: number, name: name,
                airdate: (item["airdate"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                runtime: item["runtime"] as? Int,
                summary: plainText(fromHTML: item["summary"] as? String ?? ""))
        }
        // Сортировка с номером в исходном списке: из повторов остаётся
        // первый, как бы ни была устроена сортировка.
        return parsed.enumerated()
            .sorted { ($0.element.key, $0.offset) < ($1.element.key, $1.offset) }
            .map(\.element)
            .filter { seen.insert($0.key).inserted }
    }

    /// Описания в TVMaze — HTML («<p>Ross <b>finds out</b>…</p>»).
    /// Для экрана и для модели нужен простой текст.
    public static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<br\\s*/?>|</p>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // &amp; — последним: иначе «&amp;lt;» раскодировался бы дважды.
        let entities = [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
                        ("&lt;", "<"), ("&gt;", ">"), ("&#8217;", "’"), ("&amp;", "&")]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func parseEpisodeTitle(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func secure(_ url: String) -> String {
        url.hasPrefix("http://") ? "https://" + url.dropFirst("http://".count) : url
    }
}
