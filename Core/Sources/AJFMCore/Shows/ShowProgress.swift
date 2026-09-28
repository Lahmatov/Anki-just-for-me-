import Foundation

/// Номер серии: сезон и номер в сезоне. Хранится строкой «1x3».
public struct EpisodeKey: Hashable, Comparable, Codable, Sendable {
    public var season: Int
    public var number: Int

    public init(season: Int, number: Int) {
        self.season = season
        self.number = number
    }

    public init?(raw: String) {
        let parts = raw.split(separator: "x")
        guard parts.count == 2, let season = Int(parts[0]), let number = Int(parts[1]),
              season >= 1, number >= 1 else { return nil }
        self.init(season: season, number: number)
    }

    public var raw: String { "\(season)x\(number)" }

    public var code: String {
        EpisodeRef(show: "", season: season, episode: number).code
    }

    public static func < (lhs: EpisodeKey, rhs: EpisodeKey) -> Bool {
        (lhs.season, lhs.number) < (rhs.season, rhs.number)
    }
}

/// Серия из TVMaze.
public struct EpisodeInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var season: Int
    public var number: Int
    public var name: String
    /// «1994-09-22»; nil — дата неизвестна.
    public var airdate: String?
    public var runtime: Int?
    /// Краткое описание простым текстом; пустое, если его нет.
    public var summary: String

    public init(
        id: Int, season: Int, number: Int, name: String,
        airdate: String? = nil, runtime: Int? = nil, summary: String = ""
    ) {
        self.id = id
        self.season = season
        self.number = number
        self.name = name
        self.airdate = airdate
        self.runtime = runtime
        self.summary = summary
    }

    public var key: EpisodeKey { EpisodeKey(season: season, number: number) }
    public var code: String { key.code }

    /// «S01E03 · The One with the Thumb».
    public var title: String {
        name.isEmpty ? code : "\(code) · \(name)"
    }

    /// Вышла ли серия к дню `today` («2026-09-28»). Без даты — считаем
    /// вышедшей: старые сериалы в TVMaze бывают без дат.
    public func isAired(today: String) -> Bool {
        guard let airdate else { return true }
        return airdate <= today
    }
}

/// Прогресс по сериалу: сколько посмотрено и что смотреть дальше.
public struct ShowProgress: Equatable, Sendable {
    public var episodes: [EpisodeInfo]
    public var watched: Set<EpisodeKey>
    /// Сегодня в формате «yyyy-MM-dd» — для невышедших серий.
    public var today: String

    public init(episodes: [EpisodeInfo], watched: Set<EpisodeKey>, today: String) {
        self.episodes = episodes.sorted { $0.key < $1.key }
        self.watched = watched
        self.today = today
    }

    public struct Season: Equatable, Sendable, Identifiable {
        public var number: Int
        public var episodes: [EpisodeInfo]
        public var id: Int { number }
    }

    public var seasons: [Season] {
        Dictionary(grouping: episodes, by: \.season)
            .map { Season(number: $0.key, episodes: $0.value) }
            .sorted { $0.number < $1.number }
    }

    /// Только серии, которые есть в списке: отметки об удалённых из TVMaze
    /// сериях не должны раздувать счётчик.
    public var watchedCount: Int {
        episodes.filter { watched.contains($0.key) }.count
    }

    public var airedCount: Int {
        episodes.filter { $0.isAired(today: today) }.count
    }

    /// Доля от вышедших серий: будущие не делают прогресс вечно неполным.
    public var fraction: Double {
        let aired = airedCount
        guard aired > 0 else { return 0 }
        return min(1, Double(watchedCount) / Double(aired))
    }

    /// Что смотреть дальше: первая непросмотренная вышедшая серия после
    /// последней просмотренной. Если человек пропустил серию в середине,
    /// дальше — всё равно следующая за последней: он смотрит по порядку,
    /// а пропуск — его решение.
    public var nextEpisode: EpisodeInfo? {
        let aired = episodes.filter { $0.isAired(today: today) }
        let last = aired.last { watched.contains($0.key) }?.key
        if let last, let next = aired.first(where: { $0.key > last && !watched.contains($0.key) }) {
            return next
        }
        return aired.first { !watched.contains($0.key) }
    }

    public func isSeasonWatched(_ season: Int) -> Bool {
        let aired = episodes.filter { $0.season == season && $0.isAired(today: today) }
        return !aired.isEmpty && aired.allSatisfy { watched.contains($0.key) }
    }

    /// «Посмотрел всё до этой серии включительно» — одно нажатие вместо
    /// двадцати, когда сериал начат не с приложением. Невышедшие не отмечаются.
    public func markingUpTo(_ key: EpisodeKey) -> Set<EpisodeKey> {
        watched.union(episodes.filter { $0.key <= key && $0.isAired(today: today) }.map(\.key))
    }

    /// Отметить или снять целый сезон.
    public func togglingSeason(_ season: Int) -> Set<EpisodeKey> {
        let keys = episodes.filter { $0.season == season && $0.isAired(today: today) }.map(\.key)
        return isSeasonWatched(season) ? watched.subtracting(keys) : watched.union(keys)
    }

    public static func today(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970, month = parts.month ?? 1, day = parts.day ?? 1
        return "\(year)-" + (month < 10 ? "0" : "") + "\(month)-" + (day < 10 ? "0" : "") + "\(day)"
    }
}
