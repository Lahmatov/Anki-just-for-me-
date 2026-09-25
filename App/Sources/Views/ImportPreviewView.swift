import SwiftUI
import AJFMCore

/// Превью перед записью в базу: что добавится, что пропустится, на что обратить внимание.
/// Импорт без превью — прямой путь к мусору в базе, поэтому шаг обязательный.
struct ImportPreviewView: View {
    let plan: ImportPlan
    var onConfirm: (_ includeDuplicates: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var includeDuplicates = false

    private var duplicatesFromOtherDecks: [ImportPlan.Duplicate] {
        plan.duplicates.filter { $0.existingDeckName != nil }
    }

    private var addedCount: Int {
        plan.newNotes.count + (includeDuplicates ? duplicatesFromOtherDecks.count : 0)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(tr("Набор", "Baralho", "Deck"), value: plan.deckName)
                    if !plan.folderPath.isEmpty {
                        LabeledContent(tr("Папка", "Pasta", "Folder"),
                                       value: plan.folderPath.joined(separator: " / "))
                    }
                    LabeledContent(tr("Алгоритм", "Algoritmo", "Algorithm"), value: plan.scheduler.title)
                    LabeledContent(
                        tr("Карточки", "Cartões", "Cards"),
                        value: plan.cardTypes.map(\.title).joined(separator: ", "))
                }

                Section {
                    LabeledContent(tr("Добавится слов", "Palavras a adicionar", "Words to add"),
                                   value: "\(addedCount)")
                    LabeledContent(
                        tr("Карточек", "Cartões", "Cards"),
                        value: "\(addedCount * max(plan.cardTypes.count, 1))")
                }

                if !plan.warnings.isEmpty {
                    Section(tr("Обрати внимание", "Atenção", "Heads up")) {
                        ForEach(plan.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.app(.callout))
                        }
                    }
                }

                if !plan.duplicates.isEmpty {
                    Section {
                        ForEach(Array(plan.duplicates.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.element.note.term)
                                Text(item.element.reason)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !duplicatesFromOtherDecks.isEmpty {
                            Toggle(tr("Добавить всё равно", "Adicionar mesmo assim", "Add anyway"),
                                   isOn: $includeDuplicates)
                        }
                    } header: {
                        Text(tr("Дубли", "Duplicados", "Duplicates") + " — \(plan.duplicates.count)")
                    } footer: {
                        Text(tr("Повторы внутри самого файла не добавляются никогда.",
                                "As repetições dentro do próprio ficheiro nunca são adicionadas.",
                                "Repeats within the file itself are never added."))
                    }
                }

                if !plan.newNotes.isEmpty {
                    Section(tr("Новые слова", "Palavras novas", "New words")) {
                        ForEach(Array(plan.newNotes.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.element.term).fontWeight(.medium)
                                Text(item.element.translation)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("Импорт набора", "Importar baralho", "Import deck"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Добавить", "Adicionar", "Add")) { onConfirm(includeDuplicates) }
                        .disabled(addedCount == 0)
                }
            }
        }
    }
}
