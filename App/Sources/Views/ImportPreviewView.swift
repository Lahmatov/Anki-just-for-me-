import SwiftUI
import AJFMCore

/// Превью перед записью в базу: что добавится, что пропустится, на что обратить внимание.
/// Импорт без превью — прямой путь к мусору в базе, поэтому шаг обязательный.
struct ImportPreviewView: View {
    let plan: ImportPlan
    /// Отдаёт план уже с правками из превью: название, папка, алгоритм, виды карточек.
    var onConfirm: (_ plan: ImportPlan, _ includeDuplicates: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var includeDuplicates = false
    @State private var name = ""
    @State private var folder = ""
    @State private var scheduler: SchedulerID = .fsrs6
    @State private var cardTypes: Set<CardType> = []
    @State private var loaded = false

    private var duplicatesFromOtherDecks: [ImportPlan.Duplicate] {
        plan.duplicates.filter { $0.existingDeckName != nil }
    }

    private var addedCount: Int {
        plan.newNotes.count + (includeDuplicates ? duplicatesFromOtherDecks.count : 0)
    }

    private var editedPlan: ImportPlan {
        plan.edited(name: name, folder: folder, scheduler: scheduler, cardTypes: cardTypes)
    }

    var body: some View {
        NavigationStack {
            List {
                if let cover = plan.coverURL.flatMap({ URL(string: $0) }) {
                    Section {
                        HStack(spacing: 14) {
                            CoverImage(url: cover, width: 64)
                            Text(editedPlan.deckName)
                                .font(.app(.title3))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField(tr("Название набора", "Nome do baralho", "Deck name"), text: $name)
                        .font(.app(.body, weight: .bold))
                    TextField(tr("Папка: Сериалы / Friends", "Pasta: Séries / Friends",
                                 "Folder: TV shows / Friends"), text: $folder)
                        .autocorrectionDisabled()
                } header: {
                    Text(tr("Набор", "Baralho", "Deck"))
                } footer: {
                    Text(tr("Вложенные папки — через «/». Пусто — набор ляжет в корень.",
                            "Subpastas com «/». Vazio — o baralho fica na raiz.",
                            "Nested folders with “/”. Empty puts the deck at the top level."))
                }

                Section {
                    Picker(tr("Алгоритм", "Algoritmo", "Algorithm"), selection: $scheduler) {
                        ForEach(SchedulerID.allCases, id: \.self) { id in
                            Text(id.title).tag(id)
                        }
                    }
                } footer: {
                    Text(scheduler.explanation)
                }

                Section {
                    ForEach(CardType.allCases, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { cardTypes.contains(type) },
                            set: { on in
                                // Последний вид не снимается: набор без карточек пуст.
                                if on { cardTypes.insert(type) }
                                else if cardTypes.count > 1 { cardTypes.remove(type) }
                            })
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.title).font(.app(.body, weight: .bold))
                                Text(type.explanation)
                                    .font(.app(.caption))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.primary)
                    }
                } header: {
                    Text(tr("Какие карточки сделать", "Que cartões criar", "Which cards to make"))
                } footer: {
                    Text(tr("Каждое слово даёт по карточке каждого вида: ",
                            "Cada palavra dá um cartão de cada tipo: ",
                            "Each word gets one card of each type: ")
                         + ImportPlan.cardsExplanation(words: addedCount, types: cardTypes.count)
                         + ".")
                }

                Section {
                    LabeledContent(tr("Добавится слов", "Palavras a adicionar", "Words to add"),
                                   value: "\(addedCount)")
                    LabeledContent(
                        tr("Карточек", "Cartões", "Cards"),
                        value: "\(addedCount * max(cardTypes.count, 1))")
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
                                    .foregroundStyle(Theme.muted)
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
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle(tr("Импорт набора", "Importar baralho", "Import deck"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Добавить", "Adicionar", "Add")) {
                        onConfirm(editedPlan, includeDuplicates)
                    }
                        .disabled(addedCount == 0)
                }
            }
            .onAppear {
                // Поля заполняются один раз: иначе каждое появление экрана
                // стирало бы уже внесённые правки.
                guard !loaded else { return }
                loaded = true
                name = plan.deckName
                folder = plan.folderText
                scheduler = plan.scheduler
                cardTypes = Set(plan.cardTypes)
            }
        }
    }
}

/// Постер сериала: грузится из сети, пока грузится — серая плашка с лосем
/// не нужна, хватит значка телевизора.
struct CoverImage: View {
    let url: URL
    var width: CGFloat = 44

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "tv")
                    .font(.system(size: width * 0.35, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.tint)
            }
        }
        // Пропорции постера TVMaze — 210×295.
        .frame(width: width, height: width * 295 / 210)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
