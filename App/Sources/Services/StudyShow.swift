import Foundation
import SwiftData
import AJFMCore

/// Сериал, который человек сейчас учит: по нему строится карта (P-64).
///
/// Хранится название — по нему же подписаны наборы серий («Шоу S01E03»),
/// каталог и отслеживаемые сериалы, так что одно поле связывает всё.
@MainActor
enum StudyShow {
    static var name: String? {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.studyShow),
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return raw
    }

    static func choose(_ name: String) {
        UserDefaults.standard.set(name, forKey: SettingsKey.studyShow)
        Log.info(.app, "Выбран сериал для учёбы", detail: name)
    }

    static func isCurrent(_ name: String) -> Bool {
        self.name?.lowercased() == name.lowercased()
    }

    // MARK: - Источники серий

    static func tracked(named name: String, in context: ModelContext) -> TrackedShow? {
        ShowService(context: context).all().first { $0.name.lowercased() == name.lowercased() }
    }

    static func catalogEntry(named name: String) -> CatalogIndexEntry? {
        LocalCatalog.index()?.shows.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Выбрать сериал из каталога и сразу положить слова первой серии, если
    /// их ещё нет: выбор без слов оставил бы карту пустой.
    @discardableResult
    static func start(catalog entry: CatalogIndexEntry, in context: ModelContext) throws -> ImportResult? {
        choose(entry.name)
        guard let show = LocalCatalog.show(entry), let first = show.episodes.first else { return nil }
        if LocalCatalog.installedSources(in: context)
            .contains(where: { $0.lowercased() == LocalCatalog.source(show: show, episode: first).lowercased() }) {
            return nil
        }
        return try LocalCatalog.install(episode: first, of: show, into: context)
    }

    // MARK: - Путь

    /// Карта выбранного сериала. Серии берутся у отслеживаемого сериала
    /// (все сезоны из TVMaze), иначе — из каталога (первый сезон).
    static func path(in context: ModelContext, name explicitName: String? = nil) -> ShowPath? {
        guard let name = explicitName ?? self.name else { return nil }
        let tracked = tracked(named: name, in: context)
        let catalog = catalogEntry(named: name).flatMap { LocalCatalog.show($0) }
        let catalogKeys = Set((catalog?.episodes ?? []).map { EpisodeKey(season: $0.season, number: $0.episode) })
        let stats = deckStats(showName: tracked?.name ?? catalog?.name ?? name, in: context)
        let recap = RecapService(context: context)

        let episodes: [ShowPathEpisode]
        if let tracked, !tracked.episodes.isEmpty {
            let today = ShowProgress.today()
            let watched = tracked.watched
            episodes = tracked.episodes.map { info in
                let context = EpisodeContext(showID: tracked.tvmazeID, showName: tracked.name, episode: info)
                let words = stats[info.key]
                return ShowPathEpisode(
                    key: info.key, title: info.name,
                    totalWords: words?.total ?? 0, startedWords: words?.started ?? 0,
                    catalogWords: catalogKeys.contains(info.key),
                    watched: watched.contains(info.key),
                    recapDone: recap.progress(for: context).isComplete,
                    aired: info.isAired(today: today))
            }
        } else if let catalog {
            episodes = catalog.episodes.map { item in
                let key = EpisodeKey(season: item.season, number: item.episode)
                let words = stats[key]
                return ShowPathEpisode(
                    key: key, title: item.title,
                    totalWords: words?.total ?? 0, startedWords: words?.started ?? 0,
                    catalogWords: true)
            }
        } else {
            return nil
        }
        return ShowPath(name: tracked?.name ?? catalog?.name ?? name, episodes: episodes)
    }

    /// Слов в наборе каждой серии и сколько из них начато. Набор серии
    /// узнаётся по источнику «Шоу S01E03» — его ставят каталог, сервер и свой ключ.
    static func deckStats(showName: String, in context: ModelContext)
        -> [EpisodeKey: (total: Int, started: Int)] {
        let prefix = showName.lowercased() + " "
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        var result: [EpisodeKey: (total: Int, started: Int)] = [:]
        for deck in decks {
            guard let source = deck.source?.lowercased(), source.hasPrefix(prefix),
                  let key = episodeKey(fromCode: String(source.dropFirst(prefix.count))) else { continue }
            let total = deck.notes.count
            let started = deck.notes.filter { note in note.cards.contains { $0.state != .new } }.count
            let previous = result[key] ?? (0, 0)
            // Два набора к одной серии (каталог и свой ключ) складываются.
            result[key] = (previous.total + total, previous.started + started)
        }
        return result
    }

    /// Набор к серии этого сериала, если он есть.
    static func deck(for key: EpisodeKey, showName: String, in context: ModelContext) -> Deck? {
        let source = RecapPlan.deckSource(showName: showName, season: key.season, episode: key.number)
            .lowercased()
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        return decks.first { $0.source?.lowercased() == source }
    }

    /// Готовые слова серии из каталога — одним касанием с карты.
    static func installCatalogWords(for key: EpisodeKey, showName: String, in context: ModelContext) throws {
        guard let entry = catalogEntry(named: showName), let show = LocalCatalog.show(entry),
              let item = show.episodes.first(where: { $0.season == key.season && $0.episode == key.number })
        else { return }
        try LocalCatalog.install(episode: item, of: show, into: context)
    }

    /// «s01e03» → серия 1×3; всё остальное — не серия.
    static func episodeKey(fromCode code: String) -> EpisodeKey? {
        let parts = code.uppercased().split(separator: "E")
        guard parts.count == 2, parts[0].hasPrefix("S"),
              let season = Int(parts[0].dropFirst()), let number = Int(parts[1]),
              season > 0, number > 0 else { return nil }
        return EpisodeKey(season: season, number: number)
    }
}
