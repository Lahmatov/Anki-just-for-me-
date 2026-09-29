import Foundation

/// Шаг «Recap после серии».
public enum RecapStep: String, CaseIterable, Codable, Sendable {
    /// Пять слов из серии — короткое повторение её набора.
    case words
    /// Три вопроса Мончика о серии.
    case questions
    /// Пересказ своими словами.
    case retell
}

/// Сколько шагов Recap пройдено для одной серии.
///
/// Порядок шагов — от лёгкого к трудному: сначала вспомнить слова, потом
/// ответить на вопросы, и только потом рассказать серию целиком. Но шаги
/// не запираются: пересказать можно и без слов — порядок только советует.
public struct RecapProgress: Equatable, Codable, Sendable {
    public private(set) var done: Set<RecapStep>

    public init(done: Set<RecapStep> = []) {
        self.done = done
    }

    public mutating func complete(_ step: RecapStep) {
        done.insert(step)
    }

    public func isDone(_ step: RecapStep) -> Bool {
        done.contains(step)
    }

    /// Следующий непройденный шаг по порядку; nil — Recap пройден.
    public var next: RecapStep? {
        RecapStep.allCases.first { !done.contains($0) }
    }

    public var isComplete: Bool { next == nil }

    public var fraction: Double {
        Double(done.count) / Double(RecapStep.allCases.count)
    }

    // MARK: - Хранение

    /// Строки для UserDefaults: неизвестные значения (шаг из будущей версии)
    /// пропускаются, а не ломают весь прогресс.
    public var stored: [String] {
        RecapStep.allCases.filter(done.contains).map(\.rawValue)
    }

    public init(stored: [String]) {
        self.init(done: Set(stored.compactMap(RecapStep.init(rawValue:))))
    }
}

/// Правила Recap, которым не нужны SwiftData и экран.
public enum RecapPlan {
    /// Слов в первом шаге: пять — это пара минут, а не целая сессия.
    public static let words = 5

    /// Ключ прогресса серии: сериал и номер серии, по языку не делится.
    public static func storageKey(showID: Int, season: Int, episode: Int) -> String {
        "recap.\(showID).\(season)x\(episode)"
    }

    /// Источник набора к серии — тот же, что ставят каталог, сервер и
    /// запрос по своему ключу: «Friends S01E03».
    public static func deckSource(showName: String, season: Int, episode: Int) -> String {
        "\(showName) " + String(format: "S%02dE%02d", season, episode)
    }

    /// Карточки не больше чем для `limit` слов. У слова может быть несколько
    /// карточек (узнавание, вспоминание) — они идут вместе: «пять слов»,
    /// а не «пять карточек», из которых два слова. nil — без ограничения.
    public static func limitCards(_ cards: [QueueCard], to limit: Int?) -> [QueueCard] {
        guard let limit else { return cards }
        guard limit > 0 else { return [] }
        var notes: [String] = []
        return cards.filter { card in
            if notes.contains(card.noteID) { return true }
            guard notes.count < limit else { return false }
            notes.append(card.noteID)
            return true
        }
    }
}
