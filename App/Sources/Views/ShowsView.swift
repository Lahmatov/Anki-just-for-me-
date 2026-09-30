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
    @State private var showMovieSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.stackSpacing) {
                    ScreenTitle(tr("Сериалы и фильмы", "Séries e filmes", "Shows & movies"))
                    if shows.isEmpty {
                        MascotEmptyState(
                            mood: .hello,
                            title: tr("Что смотришь?", "O que estás a ver?", "What are you watching?"),
                            message: tr("Добавь сериал — буду подсказывать следующую серию, "
                                            + "подбирать к ней слова и обсуждать её с тобой. "
                                            + "Или возьми слова к фильму.",
                                        "Junta uma série — vou sugerir o próximo episódio, escolher "
                                            + "palavras para ele e conversar contigo sobre ele. "
                                            + "Ou tira palavras de um filme.",
                                        "Add a show — I'll suggest the next episode, pick words for "
                                            + "it and chat with you about it. Or grab words from a movie.")
                        ) {
                            VStack(spacing: 10) {
                                addButton
                                movieButton
                            }
                        }
                        .cardSurface()
                    } else {
                        ForEach(shows) { show in
                            ShowCard(show: show)
                        }
                        addButton
                        movieButton
                    }

                    CatalogStrip()

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
            .tabRootTitle(tr("Сериалы и фильмы", "Séries e filmes", "Shows & movies"))
            .navigationDestination(for: TrackedShow.self) { show in
                ShowDetailView(show: show)
            }
            .sheet(isPresented: $showSearch) {
                ShowSearchView()
            }
            .sheet(isPresented: $showMovieSearch) {
                MovieSearchView()
            }
        }
    }

    /// Фильм — рядом с сериалом, но вторичной кнопкой: сериалы — главное,
    /// с ними есть серии, пересказ и разговор с Мончиком.
    private var movieButton: some View {
        Button {
            Haptics.tap()
            showMovieSearch = true
        } label: {
            Label(tr("Слова к фильму", "Palavras de um filme", "Words from a movie"),
                  systemImage: "film")
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.chunkySecondary)
        .accessibilityIdentifier("shows.movie")
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
                        HStack(spacing: 6) {
                            Text(show.name)
                                .font(.app(.title3))
                                .foregroundStyle(Theme.ink)
                            // Сериал, по которому идёт карта, — видно сразу в списке.
                            if StudyShow.isCurrent(show.name) {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.green)
                                    .accessibilityLabel(tr("учу", "a estudar", "studying"))
                            }
                        }
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
