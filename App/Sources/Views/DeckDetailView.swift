import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AJFMCore

struct DeckDetailView: View {
    let deck: Deck
    var onExport: (ExportedFile) -> Void

    @Environment(\.modelContext) private var context
    @State private var exportError: String?
    @State private var showSubtitleImporter = false
    @State private var enrichResult: EnrichService.Result?

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

            Section {
                let missing = EnrichService(context: context).notesWithoutExamples(in: deck)
                Button("Добавить примеры из субтитров", systemImage: "text.quote") {
                    showSubtitleImporter = true
                }
                .disabled(missing.isEmpty)
                if !missing.isEmpty {
                    Text("Без живого примера: \(missing.count) слов")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Подставит фразы из серии вместо словарных примеров. "
                     + "Фраза из сцены, которую ты видел, запоминается лучше.")
            }

            Section("Слова (\(notes.count))") {
                ForEach(notes) { note in
                    NavigationLink {
                        NoteDetailView(note: note)
                    } label: {
                        NoteRow(note: note)
                    }
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
        .fileImporter(
            isPresented: $showSubtitleImporter,
            allowedContentTypes: [.plainText, .text, .data]
        ) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let raw = String(data: data, encoding: .utf8),
                  let track = try? SubtitleParser.parse(raw) else {
                exportError = "Не удалось прочитать субтитры."
                return
            }
            enrichResult = EnrichService(context: context).enrich(deck: deck, with: track)
        }
        .alert(
            "Примеры добавлены",
            isPresented: Binding(
                get: { enrichResult != nil }, set: { if !$0 { enrichResult = nil } })
        ) {
            Button("Хорошо") { enrichResult = nil }
        } message: {
            if let enrichResult {
                Text("Дополнено слов: \(enrichResult.enriched). "
                     + "Не нашлось в субтитрах: \(enrichResult.skipped).")
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.term).fontWeight(.medium)
                if let ipa = note.ipa, !ipa.isEmpty {
                    Text(ipa).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SpeakButton(text: note.term, compact: true)
                Text("\(note.cards.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(note.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
