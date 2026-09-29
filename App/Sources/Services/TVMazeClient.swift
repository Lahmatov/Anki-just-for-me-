import Foundation
import AJFMCore

/// Постер и название серии из TVMaze.
///
/// Необязательное украшение: при любой ошибке или медленной сети набор
/// создаётся без картинки и с именем «S01E03». Таймаут короткий — человек
/// уже ждал ответа модели, и ждать ещё ради картинки незачем.
struct TVMazeClient {
    var session: URLSession = .shared
    var timeout: TimeInterval = 4

    struct Info: Equatable {
        var showID: Int?
        var title: String?
        var poster: String?
    }

    func lookup(_ episode: EpisodeRef) async -> Info {
        guard let searchURL = TVMaze.showSearchURL(episode.show),
              let showData = await fetch(searchURL),
              let show = TVMaze.parseShow(showData) else {
            Log.info(.network, "TVMaze: сериал не найден", detail: episode.show)
            return Info()
        }
        var info = Info(showID: show.id, poster: show.posterURL)
        if let url = TVMaze.episodeURL(
                showID: show.id, season: episode.season, episode: episode.episode),
           let data = await fetch(url) {
            info.title = TVMaze.parseEpisodeTitle(data)
        }
        Log.info(.network, "TVMaze: \(show.name) \(episode.code)",
                 detail: info.title ?? "без названия серии")
        return info
    }

    private func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
