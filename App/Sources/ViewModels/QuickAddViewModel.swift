import Foundation
import SwiftData
import Observation
import AJFMCore

/// Быстрое добавление одного слова: поля формы, проверка дублей, запись.
@Observable
@MainActor
final class QuickAddViewModel {
    var term = ""
    var translation = ""
    var example = ""
    var note = ""
    var selectedDeckID: PersistentIdentifier?
    var newDeckName = QuickAddViewModel.defaultDeckName
    private(set) var duplicateWarning: String?
    private(set) var saveError: String?

    /// Набор для слов, добавленных руками, — «из головы», а не из серии.
    static var defaultDeckName: String { tr("Из головы", "Da minha cabeça", "From my head") }

    private var trimmedTerm: String { term.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTranslation: String { translation.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool { !trimmedTerm.isEmpty && !trimmedTranslation.isEmpty }

    /// Первый набор — по умолчанию: чаще всего слово идёт туда же, что и прошлое.
    func preselect(from decks: [Deck]) {
        if selectedDeckID == nil { selectedDeckID = decks.first?.persistentModelID }
    }

    func checkDuplicate(in context: ModelContext) {
        let normalized = TermNormalizer.normalize(term)
        guard !normalized.isEmpty else {
            duplicateWarning = nil
            return
        }
        let existing = (try? context.fetch(FetchDescriptor<Note>()))?
            .first { $0.normalizedTerm == normalized }
        duplicateWarning = existing.map {
            let deckName = $0.deck?.name ?? tr("без набора", "sem baralho", "no deck")
            return tr("Уже есть в наборе «\(deckName)»", "Já existe no baralho «\(deckName)»",
                      "Already in the deck “\(deckName)”")
        }
    }

    /// Записать слово с карточками всех типов набора. false — не записалось,
    /// причина в `saveError`.
    @discardableResult
    func save(in context: ModelContext, decks: [Deck]) -> Bool {
        guard canSave else { return false }
        let data = NoteData(
            term: trimmedTerm,
            translation: trimmedTranslation,
            example: example.isEmpty ? nil : example,
            cloze: example.isEmpty ? nil : SentenceMiner.makeCloze(sentence: example, term: trimmedTerm),
            note: note.isEmpty ? nil : note,
            tags: [tr("вручную", "manual", "manual")])

        let deck = targetDeck(in: context, decks: decks)
        let note = Note(data: data)
        context.insert(note)
        note.deck = deck

        for type in deck.cardTypes {
            // Пропуск без примера не из чего собрать.
            if type == .cloze, (data.cloze ?? "").isEmpty { continue }
            let card = Card(type: type)
            context.insert(card)
            card.note = note
        }

        do {
            try context.save()
        } catch {
            Log.failure(.importing, "Слово не сохранилось", error)
            saveError = error.localizedDescription
            return false
        }
        Log.info(.importing, "Слово «\(trimmedTerm)» добавлено вручную", detail: "набор: \(deck.name)")
        return true
    }

    private func targetDeck(in context: ModelContext, decks: [Deck]) -> Deck {
        if let selectedDeckID, let existing = decks.first(where: { $0.persistentModelID == selectedDeckID }) {
            return existing
        }
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = Deck(name: name.isEmpty ? Self.defaultDeckName : name,
                        scheduler: .fsrs6, cardTypes: ImportPlanner.defaultCardTypes)
        context.insert(deck)
        return deck
    }
}
