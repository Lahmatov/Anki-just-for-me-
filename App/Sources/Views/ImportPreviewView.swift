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
                    LabeledContent("Набор", value: plan.deckName)
                    if !plan.folderPath.isEmpty {
                        LabeledContent("Папка", value: plan.folderPath.joined(separator: " / "))
                    }
                    LabeledContent("Алгоритм", value: plan.scheduler.title)
                    LabeledContent(
                        "Карточки",
                        value: plan.cardTypes.map(\.title).joined(separator: ", "))
                }

                Section {
                    LabeledContent("Добавится слов", value: "\(addedCount)")
                    LabeledContent(
                        "Карточек", value: "\(addedCount * max(plan.cardTypes.count, 1))")
                }

                if !plan.warnings.isEmpty {
                    Section("Обрати внимание") {
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
                            Toggle("Добавить всё равно", isOn: $includeDuplicates)
                        }
                    } header: {
                        Text("Дубли — \(plan.duplicates.count)")
                    } footer: {
                        Text("Повторы внутри самого файла не добавляются никогда.")
                    }
                }

                if !plan.newNotes.isEmpty {
                    Section("Новые слова") {
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
            .navigationTitle("Импорт набора")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { onConfirm(includeDuplicates) }
                        .disabled(addedCount == 0)
                }
            }
        }
    }
}
