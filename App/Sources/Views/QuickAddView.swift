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
    @State private var model = QuickAddViewModel()

    var body: some View {
        RoutedStack {
            Form {
                Section {
                    TextField(tr("Слово или фраза", "Palavra ou expressão", "Word or phrase"),
                              text: $model.term)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: model.term) { _, _ in model.checkDuplicate(in: context) }
                    TextField(tr("Перевод", "Tradução", "Translation"), text: $model.translation)
                } footer: {
                    if let warning = model.duplicateWarning ?? model.saveError {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField(tr("Пример (по желанию)", "Exemplo (opcional)", "Example (optional)"),
                              text: $model.example, axis: .vertical)
                        .autocorrectionDisabled()
                    TextField(tr("Заметка (по желанию)", "Nota (opcional)", "Note (optional)"),
                              text: $model.note, axis: .vertical)
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
                                  text: $model.newDeckName)
                    } else {
                        Picker(tr("Набор", "Baralho", "Deck"), selection: $model.selectedDeckID) {
                            Text(tr("Новый набор", "Novo baralho", "New deck"))
                                .tag(PersistentIdentifier?.none)
                            ForEach(decks) { deck in
                                Text(deck.name).tag(PersistentIdentifier?.some(deck.persistentModelID))
                            }
                        }
                        if model.selectedDeckID == nil {
                            TextField(tr("Название набора", "Nome do baralho", "Deck name"),
                                      text: $model.newDeckName)
                        }
                    }
                } header: {
                    Text(tr("Куда положить", "Onde guardar", "Where to put it"))
                }
            }
            .themedScreen()
            .navigationTitle(tr("Новое слово", "Nova palavra", "New word"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Добавить", "Adicionar", "Add"), action: save).disabled(!model.canSave)
                }
            }
            .onAppear { model.preselect(from: decks) }
        }
    }

    private func save() {
        if model.save(in: context, decks: decks) { dismiss() }
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        QuickAddView()
            .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#endif
