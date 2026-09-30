import Foundation
import Observation
import AJFMCore

/// Обложки готовых сериалов — с TVMaze, по сети, когда она есть.
///
/// В приложение картинки не вшиваются: постеры принадлежат студиям, TVMaze
/// их только раздаёт, как и для сериалов, добавленных вручную. Без сети
/// плитка остаётся цветной. Найденный адрес запоминается — поиск идёт
/// один раз на сериал, дальше картинку отдаёт кеш загрузок.
@Observable
@MainActor
final class CatalogPosters {
    static let shared = CatalogPosters()

    private(set) var urls: [String: URL]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    /// Уже искали в этом запуске: неудачу не повторяем до перезапуска,
    /// а две плитки одного сериала не ищут его дважды.
    @ObservationIgnored private var tried = Set<String>()

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        let stored = defaults.dictionary(forKey: SettingsKey.catalogPosters) as? [String: String] ?? [:]
        urls = stored.compactMapValues(URL.init(string:))
    }

    func url(for entry: CatalogIndexEntry) -> URL? { urls[entry.resource] }

    func load(_ entry: CatalogIndexEntry) async {
        guard urls[entry.resource] == nil, tried.insert(entry.resource).inserted,
              let url = TVMaze.searchURL(entry.name) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let show = CatalogPoster.pick(TVMaze.parseSearch(data), name: entry.name, year: entry.year),
              let poster = show.posterURL.flatMap(URL.init(string:)) else {
            Log.info(.network, "TVMaze: обложка не найдена", detail: entry.name)
            return
        }
        remember(poster, for: entry.resource)
    }

    func remember(_ poster: URL, for resource: String) {
        urls[resource] = poster
        defaults.set(urls.mapValues(\.absoluteString), forKey: SettingsKey.catalogPosters)
    }
}
