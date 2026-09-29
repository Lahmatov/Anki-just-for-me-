import Foundation

/// Подарок Мончику за веху на карте: сундук открылся — внутри вещица,
/// которую лось носит дальше. Празднование уже было, а вручать было нечего.
public struct MonchikGift: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Эмодзи — рисунок без файлов, одинаково видный в светлой и тёмной теме.
    public var emoji: String
    /// Сколько начатых слов нужно — порог сундука на карте.
    public var words: Int

    public init(id: String, emoji: String, words: Int) {
        self.id = id
        self.emoji = emoji
        self.words = words
    }

    public var name: String {
        switch id {
        case "scarf": return tr("шарф", "cachecol", "scarf")
        case "headphones": return tr("наушники", "auscultadores", "headphones")
        case "popcorn": return tr("попкорн", "pipocas", "popcorn")
        case "cap": return tr("кепка", "boné", "cap")
        case "sunglasses": return tr("тёмные очки", "óculos de sol", "sunglasses")
        case "clapper": return tr("хлопушка режиссёра", "claquete", "clapperboard")
        case "tophat": return tr("цилиндр", "cartola", "top hat")
        case "crown": return tr("корона", "coroa", "crown")
        case "trophy": return tr("кубок", "taça", "trophy")
        default: return id
        }
    }
}

public enum MonchikGifts {
    /// По подарку на каждый сундук и финиш карты — в порядке вех.
    public static let all: [MonchikGift] = [
        MonchikGift(id: "scarf", emoji: "🧣", words: 100),
        MonchikGift(id: "headphones", emoji: "🎧", words: 250),
        MonchikGift(id: "popcorn", emoji: "🍿", words: 500),
        MonchikGift(id: "cap", emoji: "🧢", words: 1000),
        MonchikGift(id: "sunglasses", emoji: "🕶️", words: 2000),
        MonchikGift(id: "clapper", emoji: "🎬", words: 3000),
        MonchikGift(id: "tophat", emoji: "🎩", words: 5000),
        MonchikGift(id: "crown", emoji: "👑", words: 7000),
        MonchikGift(id: "trophy", emoji: "🏆", words: 10000),
    ]

    /// Что уже открыто при таком числе начатых слов.
    public static func unlocked(words: Int) -> [MonchikGift] {
        all.filter { $0.words <= words }
    }

    /// Подарок в сундуке этой остановки или nil (обычная клетка, старт).
    public static func gift(at stop: JourneyStop) -> MonchikGift? {
        guard Journey.isMilestone(stop) else { return nil }
        return all.first { $0.words == stop.threshold }
    }

    public static func gift(id: String?) -> MonchikGift? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Что надето на Мончике. Выбранное — если оно ещё открыто (слова могли
    /// быть удалены, и вещь «вернулась в сундук»); иначе самое новое открытое.
    public static func equipped(chosen: String?, words: Int) -> MonchikGift? {
        let open = unlocked(words: words)
        if chosen == takenOff { return nil }
        if let chosen = gift(id: chosen), open.contains(chosen) { return chosen }
        return open.last
    }

    /// Особое значение выбора: «без подарка» — человек снял вещь сам.
    public static let takenOff = "none"
}
