import Foundation
import SwiftData
import AJFMCore

/// «Recap после серии»: где взять слова серии и что уже пройдено.
///
/// Правила шагов — в ядре (`RecapProgress`, `RecapPlan`); здесь база,
/// каталог и хранение отметок.
@MainActor
struct RecapService {
    let context: ModelContext
    var defaults: UserDefaults = .standard

    // MARK: - Прогресс

    func progress(for episode: EpisodeContext) -> RecapProgress {
        RecapProgress(stored: defaults.stringArray(forKey: key(episode)) ?? [])
    }

    @discardableResult
    func complete(_ step: RecapStep, for episode: EpisodeContext) -> RecapProgress {
        var progress = progress(for: episode)
        progress.complete(step)
        defaults.set(progress.stored, forKey: key(episode))
        // Звезда Recap видна на карте — её путь пересчитается.
        StudyShow.invalidate()
        return progress
    }

    private func key(_ episode: EpisodeContext) -> String {
        RecapPlan.storageKey(showID: episode.showID, season: episode.episode.season,
                             episode: episode.episode.number)
    }

    // MARK: - Слова серии

    /// Набор к этой серии, если он уже есть — из каталога, по подписке или
    /// по своему ключу: у всех один и тот же источник «Шоу S01E03».
    func deck(for episode: EpisodeContext) -> Deck? {
        let source = RecapPlan.deckSource(showName: episode.showName,
                                          season: episode.episode.season,
                                          episode: episode.episode.number)
            .lowercased()
        // Без предиката: регистр названия у каталога и TVMaze может разойтись,
        // а наборов у человека — десятки, не тысячи.
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        return decks.first { $0.source?.lowercased() == source }
    }

    /// Готовый набор из каталога в приложении, если серия там есть.
    /// Название сериала сравнивается без регистра: TVMaze и каталог
    /// пишут одинаково, но «The office» из поиска не должно промахнуться.
    func catalogEpisode(for episode: EpisodeContext) -> (CatalogShowFile, CatalogEpisode)? {
        let name = episode.showName.lowercased()
        guard let entry = LocalCatalog.index()?.shows.first(where: { $0.name.lowercased() == name }),
              let show = LocalCatalog.show(entry),
              let item = show.episodes.first(where: {
                  $0.season == episode.episode.season && $0.episode == episode.episode.number
              }) else { return nil }
        return (show, item)
    }

    /// Добавить слова серии из каталога и вернуть получившийся набор.
    @discardableResult
    func installFromCatalog(for episode: EpisodeContext) throws -> Deck? {
        guard let (show, item) = catalogEpisode(for: episode) else { return nil }
        try LocalCatalog.install(episode: item, of: show, into: context)
        return deck(for: episode)
    }
}
