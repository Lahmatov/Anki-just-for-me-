import SwiftUI
import SwiftData
import AJFMCore

/// Поиск по всем словам: пригодится, когда помнишь, что слово где-то было.
struct SearchView: View {
    @Query private var notes: [Note]
    @State private var query = ""
    @State private var selectedTag: String?

    private var allTags: [String] {
        Array(Set(notes.flatMap(\.tags))).sorted()
    }

    private var results: [Note] {
        let needle = TermNormalizer.normalize(query)
        return notes.filter { note in
            let matchesTag = selectedTag == nil || note.tags.contains(selectedTag!)
            guard matchesTag else { return false }
            guard !needle.isEmpty else { return true }
            return note.normalizedTerm.contains(needle)
                || note.translation.lowercased().contains(query.lowercased())
        }
        .sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }

    var body: some View {
        List {
            if !allTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(allTags, id: \.self) { tag in
                                Button {
                                    selectedTag = selectedTag == tag ? nil : tag
                                } label: {
                                    Text("#\(tag)")
                                        .font(.app(.caption))
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedTag == tag ? .accentColor : .secondary)
                            }
                        }
                    }
                }
            }

            Section("Найдено: \(results.count)") {
                ForEach(results) { note in
                    NavigationLink {
                        NoteDetailView(note: note)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.term).fontWeight(.medium)
                            Text(note.translation)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                            if let deck = note.deck?.name {
                                Text(deck).font(.app(.caption2)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Слово или перевод")
        .navigationTitle("Поиск")
    }
}

/// Карточка слова целиком: контекст, прогресс, произношение.
struct NoteDetailView: View {
    let note: Note

    var body: some View {
        List {
            Section {
                HStack {
                    Text(note.term).font(.app(.title2, weight: .bold))
                    SpeakButton(text: note.term, compact: true)
                }
                if let ipa = note.ipa, !ipa.isEmpty {
                    Text(ipa).font(.ipa(.subheadline)).foregroundStyle(.secondary)
                }
                Text(note.translation)
                if !note.synonyms.isEmpty {
                    LabeledContent("Синонимы", value: note.synonyms.joined(separator: ", "))
                }
            }

            if let example = note.example, !example.isEmpty {
                Section("В контексте") {
                    HStack(alignment: .top) {
                        Text(example).italic()
                        SpeakButton(text: example, compact: true)
                    }
                    if let translation = note.exampleTranslation, !translation.isEmpty {
                        Text(translation).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }

            if let userNote = note.userNote, !userNote.isEmpty {
                Section("Заметка") { Text(userNote) }
            }

            Section("Прогресс") {
                ForEach(note.cards.sorted { $0.typeRaw < $1.typeRaw }) { card in
                    HStack {
                        Text(card.type.title)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(card.state.title)
                                .font(.app(.caption))
                            if card.intervalDays > 0 {
                                Text(IntervalFormatter.short(card.intervalDays * 86_400))
                                    .font(.app(.caption2))
                                    .foregroundStyle(card.isMature ? .green : .secondary)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    YouGlishScreen(word: note.term)
                } label: {
                    Label("Как это звучит у людей", systemImage: "play.rectangle")
                }
            } footer: {
                Text("Открывает YouGlish: то же слово в реальных видео "
                     + "с американским произношением.")
            }
        }
        .navigationTitle(note.term)
        .navigationBarTitleDisplayMode(.inline)
    }
}
