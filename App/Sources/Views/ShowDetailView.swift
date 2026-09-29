import SwiftUI
import SwiftData
import AJFMCore

/// Сериал: сезоны и серии с отметками «посмотрел».
struct ShowDetailView: View {
    let show: TrackedShow

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var refreshing = false
    @State private var confirmRemove = false
    @State private var error: String?
    @State private var retold: Set<EpisodeKey> = []

    private var service: ShowService { ShowService(context: context) }

    var body: some View {
        let progress = show.progress()
        List {
            Section {
                header(progress)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle") }
            }

            ForEach(progress.seasons) { season in
                Section {
                    ForEach(season.episodes) { episode in
                        row(episode, progress: progress)
                    }
                } header: {
                    HStack {
                        Text(tr("Сезон ", "Temporada ", "Season ") + "\(season.number)")
                        Spacer()
                        Button(progress.isSeasonWatched(season.number)
                               ? tr("Снять все", "Desmarcar", "Unmark all")
                               : tr("Посмотрел весь", "Vi toda", "Watched all")) {
                            Haptics.tap()
                            service.toggleSeason(season.number, in: show)
                        }
                        .font(.app(.caption, weight: .bold))
                        .textCase(nil)
                    }
                }
            }

            Section { TVMazeCredit() }
                .listRowBackground(Color.clear)
        }
        .themedScreen()
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: EpisodeContext.self) { episode in
            EpisodeView(show: show, episode: episode)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(tr("Обновить список серий", "Atualizar episódios", "Refresh episodes"),
                           systemImage: "arrow.clockwise") {
                        Task { await refresh() }
                    }
                    Button(tr("Убрать сериал", "Remover série", "Remove show"),
                           systemImage: "trash", role: .destructive) {
                        confirmRemove = true
                    }
                } label: {
                    if refreshing { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog(
            tr("Убрать «\(show.name)»?", "Remover «\(show.name)»?", "Remove “\(show.name)”?"),
            isPresented: $confirmRemove, titleVisibility: .visible
        ) {
            Button(tr("Убрать", "Remover", "Remove"), role: .destructive) {
                service.remove(show)
                dismiss()
            }
        } message: {
            Text(tr("Отметки просмотра пропадут. Наборы слов и пересказы останутся.",
                    "As marcas de visualização desaparecem. Baralhos e recontos ficam.",
                    "Watch marks will be lost. Word decks and retellings stay."))
        }
        .onAppear { retold = service.retoldEpisodes(of: show) }
    }

    private func header(_ progress: ShowProgress) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let url = show.posterURL.flatMap({ URL(string: $0) }) {
                CoverImage(url: url, width: 90)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(show.name).font(.app(.title2)).foregroundStyle(Theme.ink)
                Text("\(progress.watchedCount) / \(progress.airedCount) "
                     + tr("серий", "episódios", "episodes"))
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.muted)
                ChunkyProgressBar(value: progress.fraction, height: 12)
                if let next = progress.nextEpisode {
                    NavigationLink(value: episodeContext(for: next)) {
                        Label(tr("Дальше: ", "A seguir: ", "Next: ") + next.code,
                              systemImage: "play.fill")
                            .font(.app(.callout))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.chunky)
                }
            }
        }
        .padding()
    }

    private func row(_ episode: EpisodeInfo, progress: ShowProgress) -> some View {
        let watched = progress.watched.contains(episode.key)
        let aired = episode.isAired(today: progress.today)
        return HStack(spacing: 12) {
            Button {
                Haptics.tap()
                service.setWatched(episode.key, !watched, in: show)
            } label: {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(watched ? Theme.green : Theme.muted)
            }
            .buttonStyle(.borderless)
            .disabled(!aired)
            .accessibilityLabel(watched ? tr("Просмотрена", "Vista", "Watched")
                                        : tr("Не просмотрена", "Por ver", "Not watched"))

            NavigationLink(value: episodeContext(for: episode)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.code + (episode.name.isEmpty ? "" : " · " + episode.name))
                        .font(.app(.body, weight: watched ? .regular : .bold))
                        .foregroundStyle(aired ? Theme.ink : Theme.muted)
                        .lineLimit(2)
                    if !aired, let date = episode.airdate {
                        Text(tr("выйдет ", "estreia a ", "airs ") + date)
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                    } else if retold.contains(episode.key) {
                        Label(tr("пересказана", "recontado", "retold"),
                              systemImage: "text.bubble.fill")
                            .font(.app(.caption))
                            .foregroundStyle(Theme.purple)
                    }
                }
            }
        }
        .contextMenu {
            if aired {
                Button(tr("Посмотрел всё до этой", "Vi tudo até aqui", "Watched everything up to here"),
                       systemImage: "checkmark.circle") {
                    service.markUpTo(episode.key, in: show)
                }
            }
        }
    }

    private func episodeContext(for episode: EpisodeInfo) -> EpisodeContext {
        EpisodeContext(showID: show.tvmazeID, showName: show.name, episode: episode)
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            try await service.refresh(show)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
