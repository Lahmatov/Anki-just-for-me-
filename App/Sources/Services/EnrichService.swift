import Foundation
import SwiftData
import AJFMCore

/// Достраивание набора примерами из субтитров.
@MainActor
struct EnrichService {
    let context: ModelContext

    struct Result {
        var enriched: Int
        var skipped: Int
    }

    /// Подставляет словам из набора примеры из субтитров серии.
    ///
    /// Пример из сцены, которую ты видел, работает лучше словарной фразы:
    /// у него уже есть контекст и эмоция, за которые цепляется память.
    @discardableResult
    func enrich(deck: Deck, with track: SubtitleTrack, overwrite: Bool = false) -> Result {
        var enriched = 0
        var skipped = 0

        for note in deck.notes {
            let hasExample = !(note.example ?? "").isEmpty
            guard overwrite || !hasExample else {
                skipped += 1
                continue
            }
            guard let mined = SentenceMiner.bestSentence(for: note.term, in: track) else {
                skipped += 1
                continue
            }
            note.example = mined.sentence
            note.cloze = mined.cloze
            enriched += 1
        }

        try? context.save()
        return Result(enriched: enriched, skipped: skipped)
    }

    /// Слова набора, у которых до сих пор нет живого примера.
    func notesWithoutExamples(in deck: Deck) -> [Note] {
        deck.notes.filter { ($0.example ?? "").isEmpty }
    }
}
