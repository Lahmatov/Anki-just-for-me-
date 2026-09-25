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
                LabeledContent(tr("Алгоритм", "Algoritmo", "Algorithm"), value: deck.scheduler.title)
                LabeledContent(
                    tr("Типы карточек", "Tipos de cartão", "Card types"),
                    value: deck.cardTypes.map(\.title).joined(separator: ", "))
                if let source = deck.source, !source.isEmpty {
                    LabeledContent(tr("Источник", "Origem", "Source"), value: source)
                }
            }

            Section {
                let missing = EnrichService(context: context).notesWithoutExamples(in: deck)
                Button(tr("Добавить примеры из субтитров", "Juntar exemplos das legendas",
                          "Add examples from subtitles"),
                       systemImage: "text.quote") {
                    showSubtitleImporter = true
                }
                .disabled(missing.isEmpty)
                if !missing.isEmpty {
                    Text(tr("Без живого примера: ", "Sem exemplo real: ", "Without a real example: ")
                         + Counted.words(missing.count))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(tr("Подставит фразы из серии вместо словарных примеров. "
                            + "Фраза из сцены, которую ты видел, запоминается лучше.",
                        "Troca os exemplos de dicionário por falas do episódio. "
                            + "Uma frase de uma cena que viste fica melhor na memória.",
                        "Replaces dictionary examples with lines from the episode. "
                            + "A line from a scene you saw sticks better."))
            }

            Section(tr("Слова", "Palavras", "Words") + " (\(notes.count))") {
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
                Button(tr("Поделиться", "Partilhar", "Share"), systemImage: "square.and.arrow.up") {
                    export()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                ReviewSessionView(deck: deck)
            } label: {
                Label(tr("Учить этот набор", "Estudar este baralho", "Study this deck"),
                      systemImage: "play.fill")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
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
                exportError = tr("Не удалось прочитать субтитры.",
                                 "Não foi possível ler as legendas.",
                                 "Couldn't read the subtitles.")
                return
            }
            enrichResult = EnrichService(context: context).enrich(deck: deck, with: track)
        }
        .alert(
            tr("Примеры добавлены", "Exemplos adicionados", "Examples added"),
            isPresented: Binding(
                get: { enrichResult != nil }, set: { if !$0 { enrichResult = nil } })
        ) {
            Button(CommonText.ok) { enrichResult = nil }
        } message: {
            if let enrichResult {
                Text(tr("Дополнено слов: ", "Palavras completadas: ", "Words updated: ")
                     + "\(enrichResult.enriched). "
                     + tr("Не нашлось в субтитрах: ", "Não encontradas nas legendas: ",
                          "Not found in the subtitles: ")
                     + "\(enrichResult.skipped).")
            }
        }
        .alert(
            CommonText.failedTitle,
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            presenting: exportError
        ) { _ in
            Button(CommonText.gotIt) { exportError = nil }
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
                    Text(ipa).font(.ipa(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                SpeakButton(text: note.term, compact: true)
                Text("\(note.cards.count)")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
            Text(note.translation)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
