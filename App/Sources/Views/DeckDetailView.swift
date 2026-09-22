import SwiftUI
import SwiftData

struct DeckDetailView: View {
    let deck: Deck
    var onExport: (ExportedFile) -> Void

    @Environment(\.modelContext) private var context
    @State private var exportError: String?

    private var notes: [Note] {
        deck.notes.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Алгоритм", value: deck.scheduler.title)
                LabeledContent(
                    "Типы карточек",
                    value: deck.cardTypes.map(\.title).joined(separator: ", "))
                if let source = deck.source, !source.isEmpty {
                    LabeledContent("Источник", value: source)
                }
            }

            Section("Слова (\(notes.count))") {
                ForEach(notes) { note in
                    NoteRow(note: note)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(notes[index]) }
                    try? context.save()
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Поделиться", systemImage: "square.and.arrow.up") { export() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                ReviewSessionView(deck: deck)
            } label: {
                Label("Учить этот набор", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .alert(
            "Не получилось",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            presenting: exportError
        ) { _ in
            Button("Понятно") { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func export() {
        do {
            onExport(ExportedFile(url: try ExportService(context: context).writeDeckFile(deck)))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct NoteRow: View {
    let note: Note
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.term).fontWeight(.medium)
                if let ipa = note.ipa, !ipa.isEmpty {
                    Text(ipa).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(note.cards.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(note.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if expanded {
                if let example = note.example, !example.isEmpty {
                    Text(example).font(.caption).italic()
                }
                if let translation = note.exampleTranslation, !translation.isEmpty {
                    Text(translation).font(.caption).foregroundStyle(.secondary)
                }
                if let userNote = note.userNote, !userNote.isEmpty {
                    Text(userNote).font(.caption).foregroundStyle(.orange)
                }
                if !note.tags.isEmpty {
                    Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { expanded.toggle() } }
    }
}
