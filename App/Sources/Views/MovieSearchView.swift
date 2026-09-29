import SwiftUI
import AJFMCore

/// Поиск фильма в каталоге Apple и набор слов к нему.
///
/// Фильм не «отслеживается», как сериал: у него нет серий, которые идут одна
/// за другой. Поэтому выбор фильма сразу ведёт к набору слов.
struct MovieSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Movie] = []
    @State private var searching = false
    @State private var error: String?
    @State private var picked: Movie?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { MascotSays(mood: .oops, text: error, size: 64) }
                        .listRowBackground(Color.clear)
                } else if results.isEmpty, !searching {
                    Section {
                        MascotSays(mood: .hello,
                                   text: tr("Напиши название фильма по-английски — подберу к нему слова.",
                                            "Escreve o título do filme em inglês — escolho palavras para ele.",
                                            "Type the movie's English title and I'll pick words for it."),
                                   size: 64)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(results) { movie in
                    Button {
                        Haptics.tap()
                        picked = movie
                    } label: {
                        row(movie)
                    }
                    .accessibilityIdentifier("movie.\(movie.id)")
                }
            }
            .themedScreen()
            .overlay {
                if searching { MonchikLoader(large: true) }
            }
            .animation(.app, value: results)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: tr("Inception, The Matrix…", "Inception, The Matrix…",
                                   "Inception, The Matrix…"))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(tr("Найти фильм", "Procurar filme", "Find a movie"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { dismiss() }
                }
            }
            .sheet(item: $picked) { movie in
                DeckRequestView(movie: movie)
            }
        }
    }

    private func row(_ movie: Movie) -> some View {
        HStack(spacing: 12) {
            if let url = movie.posterURL.flatMap({ URL(string: $0) }) {
                CoverImage(url: url, width: 40)
            } else {
                IconBadge(systemName: "film", color: Theme.purple, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.app(.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let year = movie.year {
                    Text(String(year))
                        .font(.app(.caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.primary)
        }
    }

    private func search() async {
        searching = true
        error = nil
        defer { searching = false }
        do {
            results = try await MovieSearchClient().search(query)
            if results.isEmpty {
                error = tr("Ничего не нашлось. Попробуй английское название.",
                           "Nada encontrado. Tenta o título em inglês.",
                           "Nothing found. Try the English title.")
            }
        } catch is CancellationError {
            // Поиск сменился новым — старый результат не нужен.
        } catch {
            self.error = error.localizedDescription
        }
    }
}
