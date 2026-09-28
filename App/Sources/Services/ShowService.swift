import Foundation
import SwiftData
import AJFMCore

/// Сериалы, которые человек смотрит: поиск, добавление, отметки просмотра.
///
/// Сеть — только поиск и список серий из TVMaze. Всё остальное — отметки,
/// прогресс, следующая серия — работает без сети по сохранённому снимку.
@MainActor
struct ShowService {
    let context: ModelContext
    var session: URLSession = .shared

    enum ShowError: LocalizedError {
        case network
        case noEpisodes

        var errorDescription: String? {
            switch self {
            case .network:
                return tr("Не получилось связаться с TVMaze. Проверь интернет.",
                          "Não foi possível contactar o TVMaze. Verifica a ligação.",
                          "Couldn't reach TVMaze. Check your connection.")
            case .noEpisodes:
                return tr("У этого сериала в TVMaze нет списка серий.",
                          "Esta série não tem lista de episódios no TVMaze.",
                          "This show has no episode list on TVMaze.")
            }
        }
    }

    // MARK: - Сеть

    func search(_ query: String) async throws -> [TVMaze.Show] {
        guard let url = TVMaze.searchURL(query) else { return [] }
        return TVMaze.parseSearch(try await fetch(url))
    }

    private func episodes(of showID: Int) async throws -> [EpisodeInfo] {
        guard let url = TVMaze.episodesURL(showID: showID) else { throw ShowError.network }
        let episodes = TVMaze.parseEpisodes(try await fetch(url))
        guard !episodes.isEmpty else { throw ShowError.noEpisodes }
        return episodes
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ShowError.network
            }
            return data
        } catch let error as ShowError {
            throw error
        } catch {
            Log.failure(.network, "TVMaze не ответил", error)
            throw ShowError.network
        }
    }

    // MARK: - База

    func all() -> [TrackedShow] {
        (try? context.fetch(FetchDescriptor<TrackedShow>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))) ?? []
    }

    func tracked(id: Int) -> TrackedShow? {
        let descriptor = FetchDescriptor<TrackedShow>(predicate: #Predicate { $0.tvmazeID == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Добавляет сериал со списком серий. Уже добавленный не дублируется —
    /// у него только обновляется список серий.
    @discardableResult
    func add(_ show: TVMaze.Show) async throws -> TrackedShow {
        let list = try await episodes(of: show.id)
        return try store(show, episodes: list)
    }

    /// Запись без сети — отдельно, чтобы проверять её тестами.
    @discardableResult
    func store(_ show: TVMaze.Show, episodes: [EpisodeInfo]) throws -> TrackedShow {
        if let existing = tracked(id: show.id) {
            existing.episodes = episodes
            try context.save()
            return existing
        }
        let tracked = TrackedShow(show: show, episodes: episodes)
        context.insert(tracked)
        try context.save()
        Log.info(.app, "Сериал добавлен", detail: "\(show.name), серий: \(episodes.count)")
        return tracked
    }

    /// Новые серии выходят — список обновляется по кнопке, отметки остаются.
    func refresh(_ show: TrackedShow) async throws {
        show.episodes = try await episodes(of: show.tvmazeID)
        try context.save()
    }

    func remove(_ show: TrackedShow) {
        context.delete(show)
        try? context.save()
    }

    // MARK: - Отметки

    func setWatched(_ key: EpisodeKey, _ watched: Bool, in show: TrackedShow) {
        var set = show.watched
        if watched { set.insert(key) } else { set.remove(key) }
        show.watched = set
        try? context.save()
    }

    func markUpTo(_ key: EpisodeKey, in show: TrackedShow) {
        show.watched = show.progress().markingUpTo(key)
        try? context.save()
    }

    func toggleSeason(_ season: Int, in show: TrackedShow) {
        show.watched = show.progress().togglingSeason(season)
        try? context.save()
    }

    // MARK: - Пересказы

    /// Какие серии этого сериала уже пересказаны — для галочки в списке.
    func retoldEpisodes(of show: TrackedShow) -> Set<EpisodeKey> {
        let id: Int? = show.tvmazeID
        let descriptor = FetchDescriptor<RetellSession>(predicate: #Predicate { $0.showID == id })
        let sessions = (try? context.fetch(descriptor)) ?? []
        return Set(sessions.compactMap { $0.episodeKeyRaw.flatMap(EpisodeKey.init(raw:)) })
    }
}
