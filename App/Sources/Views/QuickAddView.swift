import SwiftUI
import SwiftData
import AJFMCore

/// Быстрое добавление одного слова.
///
/// Самая частая причина, по которой такие приложения бросают, — карточки
/// слишком долго делать. Основной путь здесь другой (набор приходит готовым),
/// но увидел слово в книге — и заводить ради него целый файл бессмысленно.
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var decks: [Deck]

    @State private var term = ""
    @State private var translation = ""
    @State private var example = ""
    @State private var note = ""
    @State private var selectedDeckID: PersistentIdentifier?
    @State private var newDeckName = "Из головы"
    @State private var duplicateWarning: String?

    private var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTerm.isEmpty
            && !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Слово или фраза", text: $term)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: term) { _, _ in checkDuplicate() }
                    TextField("Перевод", text: $translation)
                } footer: {
                    if let duplicateWarning {
                        Label(duplicateWarning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("Пример (по желанию)", text: $example, axis: .vertical)
                        .autocorrectionDisabled()
                    TextField("Заметка (по желанию)", text: $note, axis: .vertical)
                } footer: {
                    Text("Пример сильно помогает запоминанию. Если его нет сейчас — "
                         + "потом подставится из субтитров серии.")
                }

                Section {
                    if decks.isEmpty {
                        TextField("Название набора", text: $newDeckName)
                    } else {
                        Picker("Набор", selection: $selectedDeckID) {
                            Text("Новый набор").tag(PersistentIdentifier?.none)
                            ForEach(decks) { deck in
                                Text(deck.name).tag(PersistentIdentifier?.some(deck.persistentModelID))
                            }
                        }
                        if selectedDeckID == nil {
                            TextField("Название набора", text: $newDeckName)
                        }
                    }
                } header: {
                    Text("Куда положить")
                }
            }
            .navigationTitle("Новое слово")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                selectedDeckID = decks.first?.persistentModelID
            }
        }
    }

    private func checkDuplicate() {
        let normalized = TermNormalizer.normalize(term)
        guard !normalized.isEmpty else {
            duplicateWarning = nil
            return
        }
        let existing = (try? context.fetch(FetchDescriptor<Note>()))?
            .first { $0.normalizedTerm == normalized }
        duplicateWarning = existing.map {
            "Уже есть в наборе «\($0.deck?.name ?? "без набора")»"
        }
    }

    private func save() {
        let data = NoteData(
            term: trimmedTerm,
            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
            example: example.isEmpty ? nil : example,
            cloze: example.isEmpty
                ? nil
                : SentenceMiner.makeCloze(sentence: example, term: trimmedTerm),
            note: note.isEmpty ? nil : note,
            tags: ["вручную"])

        let deck = targetDeck()
        let note = Note(data: data)
        context.insert(note)
        note.deck = deck

        for type in deck.cardTypes {
            if type == .cloze, (data.cloze ?? "").isEmpty { continue }
            let card = Card(type: type)
            context.insert(card)
            card.note = note
        }

        try? context.save()
        Log.info(.importing, "Слово «\(trimmedTerm)» добавлено вручную",
                 detail: "набор: \(deck.name)")
        dismiss()
    }

    private func targetDeck() -> Deck {
        if let selectedDeckID, let existing = decks.first(
            where: { $0.persistentModelID == selectedDeckID }) {
            return existing
        }
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = Deck(
            name: name.isEmpty ? "Из головы" : name,
            scheduler: .fsrs6,
            cardTypes: ImportPlanner.defaultCardTypes)
        context.insert(deck)
        return deck
    }
}
