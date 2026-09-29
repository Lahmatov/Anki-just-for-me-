import SwiftUI
import SwiftData
import AJFMCore

/// Поиск сериала в TVMaze и добавление в «Мои сериалы».
struct ShowSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [TVMaze.Show] = []
    @State private var searching = false
    @State private var adding: Int?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { MascotSays(mood: .oops, text: error, size: 64) }
                        .listRowBackground(Color.clear)
                }
                ForEach(results) { show in
                    Button {
                        Task { await add(show) }
                    } label: {
                        HStack(spacing: 12) {
                            if let url = show.posterURL.flatMap({ URL(string: $0) }) {
                                CoverImage(url: url, width: 40)
                            } else {
                                IconBadge(systemName: "tv", color: Theme.blue, size: 40)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(show.name)
                                    .font(.app(.body, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                if let year = show.premieredYear {
                                    Text(String(year))
                                        .font(.app(.caption))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                            if adding == show.id {
                                ProgressView()
                            } else if ShowService(context: context).tracked(id: show.id) != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.green)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                    }
                    .disabled(adding != nil)
                }
                if !results.isEmpty {
                    Section { TVMazeCredit() }
                        .listRowBackground(Color.clear)
                }
            }
            .themedScreen()
            .overlay {
                if searching { ProgressView() }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: tr("Friends, The Office…", "Friends, The Office…",
                                   "Friends, The Office…"))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(tr("Найти сериал", "Procurar série", "Find a show"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { dismiss() }
                }
            }
        }
    }

    private func search() async {
        searching = true
        error = nil
        defer { searching = false }
        do {
            results = try await ShowService(context: context).search(query)
            if results.isEmpty {
                error = tr("Ничего не нашлось. Попробуй английское название.",
                           "Nada encontrado. Tenta o título em inglês.",
                           "Nothing found. Try the English title.")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add(_ show: TVMaze.Show) async {
        adding = show.id
        defer { adding = nil }
        do {
            try await ShowService(context: context).add(show)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.failure()
            self.error = error.localizedDescription
        }
    }
}
