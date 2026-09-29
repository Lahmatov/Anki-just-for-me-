import SwiftUI
import SwiftData
import AJFMCore

/// Популярные сериалы с готовыми наборами — лента постеров на вкладке
/// «Сериалы». Наборы из каталога бесплатны: их отдаёт сервер Recap.
struct CatalogStrip: View {
    @Environment(\.modelContext) private var context
    @State private var shows: [BackendAPI.CatalogShow] = []
    @State private var adding: Int?

    var body: some View {
        Group {
            if !shows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CardSectionHeader(title: tr("Готовые наборы", "Baralhos prontos", "Ready decks"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(shows) { show in
                                item(show)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .task {
            guard RecapBackend.isConfigured, shows.isEmpty else { return }
            shows = (try? await RecapBackend.shared.catalog()) ?? []
        }
    }

    private func item(_ show: BackendAPI.CatalogShow) -> some View {
        let tracked = ShowService(context: context).tracked(id: show.showId) != nil
        return Button {
            guard !tracked else { return }
            Task { await add(show) }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    if let url = show.posterUrl.flatMap({ URL(string: $0) }) {
                        CoverImage(url: url, width: 88)
                    } else {
                        IconBadge(systemName: "tv", color: Theme.blue, size: 88)
                    }
                    Image(systemName: tracked ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tracked ? Theme.green : Theme.primary)
                        .background(Circle().fill(Theme.surface))
                        .offset(x: 6, y: -6)
                    if adding == show.showId {
                        ProgressView().frame(width: 88, height: 124)
                    }
                }
                Text(show.name)
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
                Text(Counted.decks(show.decks))
                    .font(.app(.caption2))
                    .foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .disabled(adding != nil)
    }

    private func add(_ show: BackendAPI.CatalogShow) async {
        adding = show.showId
        defer { adding = nil }
        do {
            try await ShowService(context: context).add(TVMaze.Show(
                id: show.showId, name: show.name, posterURL: show.posterUrl,
                premieredYear: show.year))
            Haptics.success()
        } catch {
            Haptics.failure()
        }
    }
}
