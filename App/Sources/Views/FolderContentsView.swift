import SwiftUI
import SwiftData

/// Содержимое одной папки: вложенные папки и наборы. `folder == nil` — корень.
struct FolderContentsView: View {
    let folder: Folder?
    var onExport: (ExportedFile) -> Void

    @Environment(\.modelContext) private var context
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
                ContentUnavailableView(
                    "Пусто",
                    systemImage: "tray",
                    description: Text(
                        folder == nil
                        ? "Попроси Claude сделать набор карточек и импортируй файл через меню наверху."
                        : "В этой папке пока ничего нет.")
                )
            }

            if !childFolders.isEmpty {
                Section("Папки") {
                    ForEach(childFolders) { child in
                        NavigationLink {
                            FolderContentsView(folder: child, onExport: onExport)
                                .navigationTitle(child.name)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(child.name)
                                    Text("\(child.totalNoteCount) слов")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder")
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
        VStack(alignment: .leading, spacing: 2) {
            Text(deck.name)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let cards = deck.notes.reduce(0) { $0 + $1.cards.count }
        return "\(deck.notes.count) слов · \(cards) карточек · \(deck.scheduler.title)"
    }
}
