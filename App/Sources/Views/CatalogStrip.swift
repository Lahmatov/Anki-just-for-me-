import SwiftUI
import SwiftData
import AJFMCore

/// Популярные сериалы с готовыми наборами — лента на вкладке «Сериалы».
///
/// Наборы вшиты в приложение (`LocalCatalog`): открываются без сервера,
/// без ключа и без подписки, набор к серии добавляется мгновенно.
struct CatalogStrip: View {
    @State private var shows: [CatalogIndexEntry] = []

    var body: some View {
        // VStack, а не Group: у пустой Group модификатор `.onAppear` не на
        // чем запустить — список не загружался, и лента не появлялась вовсе.
        VStack(alignment: .leading, spacing: 0) {
            if !shows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CardSectionHeader(title: tr("Готовые наборы", "Baralhos prontos", "Ready decks"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(shows) { show in
                                NavigationLink {
                                    CatalogShowView(entry: show)
                                } label: {
                                    CatalogTile(entry: show)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("catalog.\(show.rank)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear {
            if shows.isEmpty { shows = LocalCatalog.index()?.shows ?? [] }
        }
    }
}

/// Плитка сериала: постер TVMaze, пока его нет (или нет сети) — цветная
/// обложка с названием. Название поверх постера — на затемнении снизу:
/// по одной картинке сериал узнают не все, а высота плитки не меняется.
struct CatalogTile: View {
    let entry: CatalogIndexEntry

    private static let palette: [Color] = [Theme.blue, Theme.orange, Theme.purple, Theme.green,
                                           Theme.red, Theme.moose, Theme.primary]

    private var posters: CatalogPosters { .shared }

    var body: some View {
        let color = Self.palette[entry.rank % Self.palette.count]
        VStack(spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.gradient)
                Image(systemName: "tv")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
                if let url = posters.url(for: entry) {
                    AsyncImage(url: url, transaction: Transaction(animation: .appQuick)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .overlay(alignment: .bottom) {
                                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                                   startPoint: .top, endPoint: .bottom)
                                        .frame(height: 64)
                                }
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 96, height: 132)
                }
                Text(entry.name)
                    .font(.app(.subheadline, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .padding(8)
            }
            .frame(width: 96, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(Counted.words(entry.words))
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
        .task { await posters.load(entry) }
    }
}

/// Сериал из каталога: серии первого сезона, у каждой — число слов и кнопка
/// «Добавить». Добавленная серия отмечается галочкой.
struct CatalogShowView: View {
    let entry: CatalogIndexEntry

    @Environment(\.modelContext) private var context
    @State private var show: CatalogShowFile?
    @State private var installed: Set<String> = []
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: Design.stackSpacing) {
                if let show {
                    header(show)
                    ForEach(show.episodes) { episode in
                        row(episode, of: show)
                    }
                } else if failed {
                    MascotEmptyState(
                        mood: .oops,
                        title: tr("Не открылся", "Não abriu", "Couldn't open"),
                        message: tr("Файл сериала повреждён. Переустанови приложение.",
                                    "O ficheiro da série está danificado. Reinstala a aplicação.",
                                    "The show file is damaged. Reinstall the app.")) { EmptyView() }
                        .cardSurface()
                } else {
                    MonchikLoader(large: true).padding(40)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard show == nil else { return }
            show = LocalCatalog.show(entry)
            failed = show == nil
            installed = LocalCatalog.installedSources(in: context)
        }
    }

    private func header(_ show: CatalogShowFile) -> some View {
        let missing = show.episodes.filter { !installed.contains(LocalCatalog.source(show: show, episode: $0)) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Сезон 1", "Temporada 1", "Season 1"))
                    .font(.app(.title3, weight: .heavy))
                Spacer()
                HintButton(text: tr("Слова подобраны заранее к каждой серии: фразовые глаголы, идиомы, "
                                        + "живые выражения. Без ИИ и без сети — набор добавляется сразу.",
                                    "As palavras foram escolhidas para cada episódio: phrasal verbs, "
                                        + "expressões idiomáticas, linguagem do dia a dia. Sem IA e sem "
                                        + "rede — o baralho entra logo.",
                                    "Words are picked in advance for each episode: phrasal verbs, idioms, "
                                        + "everyday expressions. No AI, no network — the deck is added "
                                        + "right away."))
            }
            Text(Counted.words(entry.words) + " · " + tr("серий: ", "episódios: ", "episodes: ")
                 + "\(show.episodes.count)")
                .font(.app(.subheadline))
                .foregroundStyle(Theme.muted)
            StudyThisShowButton(name: show.name) {
                // Из каталога — сразу со словами первой серии, как в знакомстве.
                if let entry = LocalCatalog.index()?.shows.first(where: { $0.name == show.name }) {
                    try? StudyShow.start(catalog: entry, in: context)
                    installed = LocalCatalog.installedSources(in: context)
                }
            }
            if missing.count > 1 {
                Button {
                    add(missing, of: show)
                } label: {
                    Text(tr("Добавить весь сезон", "Juntar a temporada toda", "Add the whole season"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky)
                .accessibilityIdentifier("catalog.addAll")
            }
        }
        .cardSurface()
    }

    private func row(_ episode: CatalogEpisode, of show: CatalogShowFile) -> some View {
        let done = installed.contains(LocalCatalog.source(show: show, episode: episode))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.code)
                    .font(.app(.caption, weight: .heavy))
                    .foregroundStyle(Theme.muted)
                Text(episode.title.isEmpty ? episode.code : episode.title)
                    .font(.app(.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Counted.words(episode.notes.count))
                    .font(.app(.caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .accessibilityLabel(tr("Добавлено", "Adicionado", "Added"))
            } else {
                Button {
                    add([episode], of: show)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .heavy))
                }
                .buttonStyle(ChunkyButtonStyle(kind: .primary, horizontalPadding: 14))
                .accessibilityLabel(tr("Добавить набор", "Juntar baralho", "Add deck"))
                .accessibilityIdentifier("catalog.add.\(episode.episode)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func add(_ episodes: [CatalogEpisode], of show: CatalogShowFile) {
        do {
            for episode in episodes {
                try LocalCatalog.install(episode: episode, of: show, into: context)
                installed.insert(LocalCatalog.source(show: show, episode: episode))
            }
            Haptics.success()
        } catch {
            Log.failure(.importing, "Набор из каталога не добавился", error)
            Haptics.failure()
        }
    }
}
