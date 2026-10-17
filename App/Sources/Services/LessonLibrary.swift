import Foundation
import SwiftData
import AJFMCore

/// Уроки — наборы в папке «Уроки» (P-68) — и их место на карте уроков (P-69).
@MainActor
enum LessonLibrary {

    static func decks(in context: ModelContext) -> [Deck] {
        let all = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        return all.filter { DeckRequest.isLessonFolder($0.folder?.path) }
    }

    /// Ключ урока для результата теста. У набора нет своего номера, а дата
    /// создания и имя не меняются сами; переименовал урок — тест заново.
    static func key(for deck: Deck) -> String {
        "\(Int(deck.createdAt.timeIntervalSince1970))|\(deck.name)"
    }

    static func notes(of deck: Deck) -> [NoteData] {
        deck.notes.sorted { $0.createdAt < $1.createdAt }.map(\.asNoteData)
    }

    static func step(for deck: Deck) -> LessonStep {
        let started = deck.notes.filter { note in note.cards.contains { $0.state != .new } }.count
        return LessonStep(id: key(for: deck), name: deck.name, createdAt: deck.createdAt,
                          totalWords: deck.notes.count, startedWords: started,
                          bestQuiz: bestQuiz(for: deck))
    }

    static func path(in context: ModelContext) -> LessonPath {
        LessonPath(steps: decks(in: context).map(step(for:)))
    }

    // MARK: - Мини-тест

    private static var scores: [String: Double] {
        UserDefaults.standard.dictionary(forKey: SettingsKey.lessonQuizScores) as? [String: Double] ?? [:]
    }

    static func bestQuiz(for deck: Deck) -> Double? {
        scores[key(for: deck)]
    }

    /// Запоминается лучший результат: слабая попытка не отнимает пройденный урок.
    @discardableResult
    static func record(quiz score: Double, for deck: Deck) -> Bool {
        var all = scores
        let key = key(for: deck)
        let improved = score > (all[key] ?? -1)
        if improved {
            all[key] = score
            UserDefaults.standard.set(all, forKey: SettingsKey.lessonQuizScores)
        }
        return improved
    }
}
