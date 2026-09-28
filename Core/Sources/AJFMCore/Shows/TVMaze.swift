import Foundation

/// TVMaze — бесплатная открытая база сериалов, без ключа.
///
/// Отсюда постер для набора и настоящее название серии. Запросы только
/// читают и несут одно название сериала; при любой ошибке набор просто
/// остаётся без картинки — ради неё не стоит ронять импорт.
public enum TVMaze {
    public static let host = "https://api.tvmaze.com"

    public struct Show: Equatable, Sendable {
        public var id: Int
        public var name: String
        public var posterURL: String?
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
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? Int,
              let name = object["name"] as? String, !name.isEmpty else { return nil }
        let images = object["image"] as? [String: Any]
        let poster = (images?["medium"] as? String) ?? (images?["original"] as? String)
        return Show(id: id, name: name, posterURL: poster.map(secure))
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
