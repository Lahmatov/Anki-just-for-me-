import Foundation

/// Серия на карте сериала.
public struct ShowPathEpisode: Equatable, Sendable, Identifiable {
    public var key: EpisodeKey
    public var title: String
    /// Слов в наборе серии; 0 — набора ещё нет.
    public var totalWords: Int
    /// Сколько из них уже начато (хотя бы одна карточка вышла из новых).
    public var startedWords: Int
    /// Набора нет, но готовые слова есть в каталоге — добавятся одним касанием.
    public var catalogWords: Bool
    public var watched: Bool
    public var recapDone: Bool
    /// Серия вышла; невышедшие видны на карте, но закрыты.
    public var aired: Bool

    public init(key: EpisodeKey, title: String = "", totalWords: Int = 0, startedWords: Int = 0,
                catalogWords: Bool = false, watched: Bool = false, recapDone: Bool = false,
                aired: Bool = true) {
        self.key = key
        self.title = title
        self.totalWords = max(totalWords, 0)
        self.startedWords = min(max(startedWords, 0), max(totalWords, 0))
        self.catalogWords = catalogWords
        self.watched = watched
        self.recapDone = recapDone
        self.aired = aired
    }

    public var id: String { key.raw }
    public var code: String { key.code }
    public var hasDeck: Bool { totalWords > 0 }

    /// Серия пройдена, когда начаты все её слова: это видно в статистике и
    /// проверяемо, в отличие от «посмотрел». Просмотр и Recap — отметки сверху.
    public var isDone: Bool { hasDeck && startedWords >= totalWords }

    public var fraction: Double {
        hasDeck ? Double(startedWords) / Double(totalWords) : 0
    }
}

/// Узел карты: серия — маленький шаг, финал сезона — большой.
public enum ShowPathNode: Equatable, Sendable, Identifiable {
    case episode(ShowPathEpisode)
    case seasonFinale(season: Int, episodes: Int, done: Bool)

    public var id: String {
        switch self {
        case .episode(let episode): return "e" + episode.id
        case .seasonFinale(let season, _, _): return "s\(season)"
        }
    }
}

/// Карта одного сериала: шаги — серии, большие остановки — сезоны.
///
/// Раньше карта была общей для всех слов (P-57). Но учат по сериалу, и
/// путь «серия за серией» понятнее: видно, где ты в сериале и сколько до
/// конца сезона. Общий счёт слов остался — в заголовке карты и в подарках.
public struct ShowPath: Equatable, Sendable {
    public var name: String
    /// Серии по порядку сезонов и номеров. Спецвыпуски (сезон 0) не в пути:
    /// у них нет места в последовательности.
    public var episodes: [ShowPathEpisode]

    public init(name: String, episodes: [ShowPathEpisode]) {
        self.name = name
        var seen = Set<EpisodeKey>()
        self.episodes = episodes
            .filter { $0.key.season > 0 && $0.key.number > 0 && seen.insert($0.key).inserted }
            .sorted { $0.key < $1.key }
    }

    public var seasons: [Int] {
        var result: [Int] = []
        for episode in episodes where result.last != episode.key.season {
            result.append(episode.key.season)
        }
        return result
    }

    public func episodes(inSeason season: Int) -> [ShowPathEpisode] {
        episodes.filter { $0.key.season == season }
    }

    public func isSeasonDone(_ season: Int) -> Bool {
        let list = episodes(inSeason: season)
        return !list.isEmpty && list.allSatisfy(\.isDone)
    }

    public var completedSeasons: [Int] {
        seasons.filter(isSeasonDone)
    }

    /// Узлы в порядке пути: серии сезона, затем его финал.
    public var nodes: [ShowPathNode] {
        seasons.flatMap { season -> [ShowPathNode] in
            let list = episodes(inSeason: season)
            return list.map(ShowPathNode.episode)
                + [.seasonFinale(season: season, episodes: list.count, done: isSeasonDone(season))]
        }
    }

    public var doneCount: Int { episodes.filter(\.isDone).count }
    public var total: Int { episodes.count }

    /// Где фишка: первая непройденная вышедшая серия; nil — всё пройдено.
    public var current: ShowPathEpisode? {
        episodes.first { !$0.isDone && $0.aired }
    }

    /// Сезон, до финала которого дошли с прошлого раза, — для праздника.
    /// `celebrated` — сезоны, уже отпразднованные; nil — праздновать ещё не
    /// начинали (первое открытие новой карты): старое не празднуем.
    public func seasonToCelebrate(celebrated: Set<Int>?) -> Int? {
        guard let celebrated else { return nil }
        return completedSeasons.last { !celebrated.contains($0) }
    }
}
