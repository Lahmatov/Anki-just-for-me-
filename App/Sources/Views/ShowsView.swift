import SwiftUI
import SwiftData
import AJFMCore

/// Вкладка «Сериалы»: что смотрю, что дальше, и практика речи.
///
/// Сериал здесь — центр приложения: смотришь серию, отмечаешь её, берёшь
/// слова, пересказываешь и обсуждаешь с Мончиком.
struct ShowsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedShow.addedAt, order: .reverse) private var shows: [TrackedShow]
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.stackSpacing) {
                    if shows.isEmpty {
                        MascotEmptyState(
                            mood: .hello,
                            title: tr("Что смотришь?", "O que estás a ver?", "What are you watching?"),
                            message: tr("Добавь сериал — буду подсказывать следующую серию, "
                                            + "подбирать к ней слова и обсуждать её с тобой.",
                                        "Junta uma série — vou sugerir o próximo episódio, escolher "
                                            + "palavras para ele e conversar contigo sobre ele.",
                                        "Add a show — I'll suggest the next episode, pick words for "
                                            + "it and chat with you about it.")
                        ) {
                            addButton
                        }
                        .cardSurface()
                    } else {
                        ForEach(shows) { show in
                            ShowCard(show: show)
                        }
                        addButton
                    }

                    CardSectionHeader(title: tr("Практика речи", "Prática de fala", "Speaking practice"))
                    CardLink(
                        title: tr("Пересказать что угодно", "Recontar qualquer coisa", "Retell anything"),
                        subtitle: tr("С субтитрами любой серии или фильма",
                                     "Com as legendas de qualquer episódio ou filme",
                                     "With subtitles of any episode or film"),
                        systemImage: "text.bubble.fill", color: Theme.purple
                    ) { RetellView() }
                    CardLink(
                        title: tr("Минимальные пары", "Pares mínimos", "Minimal pairs"),
                        subtitle: tr("ship или sheep — тренажёр произношения",
                                     "ship ou sheep — treino de pronúncia",
                                     "ship or sheep — pronunciation drill"),
                        systemImage: "waveform", color: Theme.red
                    ) { MinimalPairsView() }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tr("Сериалы", "Séries", "TV shows"))
            .navigationDestination(for: TrackedShow.self) { show in
                ShowDetailView(show: show)
            }
            .sheet(isPresented: $showSearch) {
                ShowSearchView()
            }
        }
    }

    private var addButton: some View {
        Button {
            Haptics.tap()
            showSearch = true
        } label: {
            Label(tr("Добавить сериал", "Adicionar série", "Add a show"), systemImage: "plus")
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.chunky)
    }
}

/// Карточка сериала: постер, прогресс и следующая серия.
private struct ShowCard: View {
    let show: TrackedShow

    var body: some View {
        let progress = show.progress()
        NavigationLink(value: show) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    if let url = show.posterURL.flatMap({ URL(string: $0) }) {
                        CoverImage(url: url, width: 56)
                    } else {
                        IconBadge(systemName: "tv", color: Theme.blue, size: 56)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(show.name)
                            .font(.app(.title3))
                            .foregroundStyle(Theme.ink)
                        Text("\(progress.watchedCount) / \(progress.airedCount) "
                             + tr("серий", "episódios", "episodes"))
                            .font(.app(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        ChunkyProgressBar(value: progress.fraction, height: 10)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                }
                if let next = progress.nextEpisode {
                    Label(tr("Дальше: ", "A seguir: ", "Next: ") + next.title,
                          systemImage: "play.circle.fill")
                        .font(.app(.callout, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                } else if progress.watchedCount > 0 {
                    Label(tr("Всё просмотрено", "Tudo visto", "All caught up"),
                          systemImage: "checkmark.seal.fill")
                        .font(.app(.callout, weight: .bold))
                        .foregroundStyle(Theme.green)
                }
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
