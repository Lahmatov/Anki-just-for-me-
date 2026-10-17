import SwiftUI
import SwiftData
import AJFMCore

/// Поиск сериала в TVMaze и добавление в «Мои сериалы».
struct ShowSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var model = ShowSearchViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        RoutedStack {
            List {
                if let error = model.error {
                    Section { MascotSays(mood: .oops, text: error, size: 64) }
                        .listRowBackground(Color.clear)
                }
                ForEach(model.results) { show in
                    Button {
                        add(show)
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
                            if model.adding == show.id {
                                MonchikLoader()
                            } else if model.trackedIDs.contains(show.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.green)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                    }
                    .disabled(model.adding != nil)
                }
                if !model.results.isEmpty {
                    Section { TVMazeCredit() }
                        .listRowBackground(Color.clear)
                }
            }
            .themedScreen()
            .overlay {
                if model.searching { MonchikLoader(large: true) }
            }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: tr("Friends, The Office…", "Friends, The Office…",
                                   "Friends, The Office…"))
            .onSubmit(of: .search) { Task { await model.search(in: context) } }
            .navigationTitle(tr("Найти сериал", "Procurar série", "Find a show"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { dismiss() }
                }
            }
        }
    }

    private func add(_ show: TVMaze.Show) {
        Task {
            if await model.add(show, in: context) { dismiss() }
        }
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        ShowSearchView()
            .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#endif
