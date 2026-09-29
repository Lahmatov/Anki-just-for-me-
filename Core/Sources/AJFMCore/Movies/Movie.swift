import Foundation

/// Фильм из каталога Apple (iTunes Search API) — рядом с сериалами.
///
/// У TVMaze фильмов нет, а каталог Apple открыт без ключа. Номер фильма
/// тот же, что проверяет сервер (`backend/src/movies.ts`): приложение ищет,
/// сервер берёт сведения сам по номеру.
public struct Movie: Equatable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var year: Int?
    public var summary: String
    public var posterURL: String?

    public init(id: Int, title: String, year: Int? = nil, summary: String = "", posterURL: String? = nil) {
        self.id = id
        self.title = title
        self.year = year
        self.summary = summary
        self.posterURL = posterURL
    }

    /// «Inception (2010)» — имя набора и источник, как на сервере.
    public var label: String {
        year.map { "\(title) (\($0))" } ?? title
    }

    /// Папка наборов к фильмам — одна на все: у фильма нет сезонов.
    /// Совпадает с сервером на каждом языке, иначе наборы одного фильма
    /// по подписке и по своему ключу легли бы в разные папки.
    public static var folder: String {
        tr("Фильмы", "Filmes", "Movies")
    }

    /// Тема запроса для своего ключа: модель знает фильм по названию и году.
    public var deckTopic: String {
        "the movie \(label)"
    }

    /// Набор к фильму: папка «Фильмы», имя и источник — «Название (год)»,
    /// обложка — постер.
    public func decorate(_ file: DeckFile) -> DeckFile {
        var file = file
        file.deck.folder = Self.folder
        file.deck.name = label
        file.deck.source = label
        if let posterURL, !posterURL.isEmpty { file.deck.cover = posterURL }
        return file
    }
}

/// Поиск фильмов в каталоге Apple.
public enum AppleMovies {
    static let host = "https://itunes.apple.com"

    /// Поиск по названию. Страна — США: английские названия и американский
    /// прокат, а приложение — про американский английский.
    public static func searchURL(_ term: String, limit: Int = 25) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: host + "/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "movie"),
            URLQueryItem(name: "entity", value: "movie"),
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
        ]
        return components?.url
    }

    private struct Response: Decodable {
        var results: [Item]?
    }

    private struct Item: Decodable {
        var kind: String?
        var trackId: Int?
        var trackName: String?
        var releaseDate: String?
        var longDescription: String?
        var shortDescription: String?
        var artworkUrl100: String?
    }

    /// Результаты поиска: только фильмы, без повторов, с постером покрупнее.
    /// Битый ответ — ошибка, пустой — пустой список.
    public static func parseSearch(_ data: Data) throws -> [Movie] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<Int>()
        return (response.results ?? []).compactMap { item -> Movie? in
            guard item.kind == "feature-movie", let id = item.trackId, id > 0,
                  let title = item.trackName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, seen.insert(id).inserted else { return nil }
            return Movie(
                id: id, title: title, year: year(from: item.releaseDate),
                summary: item.longDescription ?? item.shortDescription ?? "",
                posterURL: poster(from: item.artworkUrl100))
        }
    }

    static func year(from date: String?) -> Int? {
        guard let date, date.count >= 4, let year = Int(date.prefix(4)),
              (1881..<2200).contains(year) else { return nil }
        return year
    }

    /// Картинка 100×100 мала для обложки; Apple отдаёт любой размер по имени файла.
    static func poster(from url: String?) -> String? {
        guard let url, url.hasPrefix("https://") else { return nil }
        guard let range = url.range(of: #"/\d+x\d+bb\."#, options: .regularExpression) else { return url }
        return url.replacingCharacters(in: range, with: "/600x600bb.")
    }
}
