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
    @State private var newDeckName = QuickAddView.defaultDeckName
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
                    TextField(tr("Слово или фраза", "Palavra ou expressão", "Word or phrase"),
                              text: $term)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: term) { _, _ in checkDuplicate() }
                    TextField(tr("Перевод", "Tradução", "Translation"), text: $translation)
                } footer: {
                    if let duplicateWarning {
                        Label(duplicateWarning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField(tr("Пример (по желанию)", "Exemplo (opcional)", "Example (optional)"),
                              text: $example, axis: .vertical)
                        .autocorrectionDisabled()
                    TextField(tr("Заметка (по желанию)", "Nota (opcional)", "Note (optional)"),
                              text: $note, axis: .vertical)
                } footer: {
                    Text(tr("Пример сильно помогает запоминанию. Если его нет сейчас — "
                                + "потом подставится из субтитров серии.",
                            "Um exemplo ajuda muito a memorizar. Se não tens um agora, "
                                + "entra depois a partir das legendas do episódio.",
                            "An example helps a lot with remembering. If you don't have one "
                                + "now, it can come from the episode's subtitles later."))
                }

                Section {
                    if decks.isEmpty {
                        TextField(tr("Название набора", "Nome do baralho", "Deck name"),
                                  text: $newDeckName)
                    } else {
                        Picker(tr("Набор", "Baralho", "Deck"), selection: $selectedDeckID) {
                            Text(tr("Новый набор", "Novo baralho", "New deck"))
                                .tag(PersistentIdentifier?.none)
                            ForEach(decks) { deck in
                                Text(deck.name).tag(PersistentIdentifier?.some(deck.persistentModelID))
                            }
                        }
                        if selectedDeckID == nil {
                            TextField(tr("Название набора", "Nome do baralho", "Deck name"),
                                      text: $newDeckName)
                        }
                    }
                } header: {
                    Text(tr("Куда положить", "Onde guardar", "Where to put it"))
                }
            }
            .navigationTitle(tr("Новое слово", "Nova palavra", "New word"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Добавить", "Adicionar", "Add")) { save() }.disabled(!canSave)
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
            let deckName = $0.deck?.name ?? tr("без набора", "sem baralho", "no deck")
            return tr("Уже есть в наборе «\(deckName)»", "Já existe no baralho «\(deckName)»",
                      "Already in the deck “\(deckName)”")
        }
    }

    /// Набор для слов, добавленных руками, — «из головы», а не из серии.
    static var defaultDeckName: String { tr("Из головы", "Da minha cabeça", "From my head") }

    private func save() {
        let data = NoteData(
            term: trimmedTerm,
            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
            example: example.isEmpty ? nil : example,
            cloze: example.isEmpty
                ? nil
                : SentenceMiner.makeCloze(sentence: example, term: trimmedTerm),
            note: note.isEmpty ? nil : note,
            tags: [tr("вручную", "manual", "manual")])

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
            name: name.isEmpty ? Self.defaultDeckName : name,
            scheduler: .fsrs6,
            cardTypes: ImportPlanner.defaultCardTypes)
        context.insert(deck)
        return deck
    }
}
