import SwiftUI
import SwiftData
import AJFMCore

/// Содержимое одной папки: вложенные папки и наборы. `folder == nil` — корень.
struct FolderContentsView: View {
    let folder: Folder?
    var onExport: (ExportedFile) -> Void

    @Environment(\.modelContext) private var context
    @State private var showDeckRequest = false
    @Query private var allFolders: [Folder]
    @Query private var allDecks: [Deck]

    private var childFolders: [Folder] {
        allFolders
            .filter { $0.parent?.persistentModelID == folder?.persistentModelID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var decks: [Deck] {
        allDecks
            .filter { $0.folder?.persistentModelID == folder?.persistentModelID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if childFolders.isEmpty && decks.isEmpty {
                ContentUnavailableView {
                    Label("Пока пусто", systemImage: "rectangle.stack")
                } description: {
                    Text(folder == nil
                         ? "Напиши, какую серию смотришь, — Claude подберёт слова. "
                           + "Файл набора можно открыть через меню «…»."
                         : "В этой папке пока ничего нет.")
                } actions: {
                    if folder == nil {
                        Button("Набор через Claude", systemImage: "sparkles") {
                            showDeckRequest = true
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }

            if !childFolders.isEmpty {
                Section("Папки") {
                    ForEach(childFolders) { child in
                        NavigationLink {
                            FolderContentsView(folder: child, onExport: onExport)
                                .navigationTitle(child.name)
                        } label: {
                            HStack(spacing: 14) {
                                IconBadge(systemName: "folder.fill", color: .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.name)
                                        .font(.app(.body, weight: .medium))
                                    Text(RussianPlural.words(child.totalNoteCount))
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { delete(childFolders, at: $0) }
                }
            }

            if !decks.isEmpty {
                Section("Наборы") {
                    ForEach(decks) { deck in
                        NavigationLink {
                            DeckDetailView(deck: deck, onExport: onExport)
                        } label: {
                            DeckRow(deck: deck)
                        }
                    }
                    .onDelete { delete(decks, at: $0) }
                }
            }
        }
        .sheet(isPresented: $showDeckRequest) {
            DeckRequestView()
        }
    }

    private func delete<T: PersistentModel>(_ items: [T], at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
    }
}

struct DeckRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: "rectangle.stack.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name)
                    .font(.app(.body, weight: .medium))
                Text(subtitle)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        let cards = deck.notes.reduce(0) { $0 + $1.cards.count }
        return RussianPlural.words(deck.notes.count) + " · " + RussianPlural.cards(cards)
            + " · " + deck.scheduler.title
    }
}
