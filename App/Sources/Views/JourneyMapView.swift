import SwiftUI
import SwiftData
import AJFMCore

/// Карта выбранного сериала — как поле настольной игры: маленький шаг —
/// серия, большая остановка — финал сезона, фишка с Мончиком стоит на
/// серии, которую учишь сейчас (P-64).
///
/// Серия пройдена, когда начаты все её слова — это проверяемо, в отличие
/// от «посмотрел». Просмотр и Recap — отметки на кружке. Общий счёт слов и
/// подарки Мончику остались над картой.
struct JourneyMapView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.studyShow) private var studyShow: String?
    @AppStorage(SettingsKey.monchikGift) private var chosenGift: String?

    @State private var path: ShowPath?
    @State private var tracked: TrackedShow?
    @State private var words = Journey.position(words: 0)
    @State private var matureWords = 0
    @State private var selected: ShowPathEpisode?
    @State private var pendingAction: StepAction?
    @State private var destination: MapDestination?
    @State private var deckRequest: EpisodeRequest?
    @State private var showPicker = false
    @State private var celebratedSeason: Int?
    @State private var loaded = false

    private let rowHeight: CGFloat = 96

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Design.stackSpacing) {
                    header
                    giftShelf
                    if let path, !path.nodes.isEmpty {
                        board(path)
                    } else if studyShow != nil, loaded {
                        MascotSays(mood: .oops,
                                   text: tr("У этого сериала не нашлось серий. Добавь его во вкладке «Сериалы» — "
                                                + "список серий придёт из TVMaze.",
                                            "Esta série não tem episódios. Junta-a no separador «Séries» — "
                                                + "a lista vem do TVMaze.",
                                            "No episodes found for this show. Add it on the Shows tab — "
                                                + "the episode list comes from TVMaze."),
                                   size: 72)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tr("Карта", "Mapa", "Map"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { load(scrollWith: proxy) }
        }
        .sheet(item: $selected, onDismiss: runPendingAction) { episode in
            EpisodeStepSheet(episode: episode, showName: path?.name ?? "", canOpenEpisode: tracked != nil) { action in
                pendingAction = action
                selected = nil
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPicker, onDismiss: { load(scrollWith: nil) }) {
            StudyShowPicker()
        }
        .sheet(item: $deckRequest, onDismiss: { load(scrollWith: nil) }) { request in
            DeckRequestView(initialTopic: request.topic, episode: request.episode)
        }
        .navigationDestination(item: $destination) { target in
            switch target {
            case .review(let deck): ReviewSessionView(deck: deck)
            case .episode(let show, let episode): EpisodeView(show: show, episode: episode)
            }
        }
        .overlay {
            if let season = celebratedSeason {
                CelebrationOverlay(
                    title: tr("Сезон \(season) пройден!", "Temporada \(season) concluída!", "Season \(season) done!"),
                    subtitle: tr("Все слова сезона в работе. Мончик гордится — дальше новый сезон.",
                                 "Todas as palavras da temporada em curso. O Monchik está orgulhoso.",
                                 "Every word of the season is in play. Monchik is proud — on to the next.")
                ) { celebratedSeason = nil }
                .transition(.opacity)
            }
        }
        .animation(.app, value: celebratedSeason)
    }

    // MARK: - Заголовок

    @ViewBuilder
    private var header: some View {
        if let path {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(path.name)
                        .font(.app(.title2, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button(tr("Сменить", "Mudar", "Change")) { showPicker = true }
                        .font(.app(.subheadline, weight: .bold))
                        .accessibilityIdentifier("map.change")
                }
                ChunkyProgressBar(value: path.total > 0 ? Double(path.doneCount) / Double(path.total) : 0,
                                  tint: Theme.green)
                Text(tr("Пройдено серий: \(path.doneCount) из \(path.total)",
                        "Episódios concluídos: \(path.doneCount) de \(path.total)",
                        "Episodes done: \(path.doneCount) of \(path.total)"))
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.ink)
                HintHeader(
                    title: Counted.words(words.words) + " · "
                        + tr("выучено \(matureWords)", "aprendidas \(matureWords)", "\(matureWords) learned"),
                    hint: tr("Серия пройдена, когда начаты все её слова. Финал сезона — когда пройдены все "
                                 + "его серии. Нажми на серию, чтобы учить её слова или открыть её.",
                             "Um episódio fica concluído quando todas as palavras dele estão começadas. O "
                                 + "final da temporada, quando todos os episódios estão. Toca num episódio "
                                 + "para estudar as palavras ou abri-lo.",
                             "An episode is done when all its words are started. A season finale — when all "
                                 + "its episodes are. Tap an episode to study its words or open it."))
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .cardSurface()
            .padding(.top, 8)
        } else if loaded {
            MascotEmptyState(
                mood: .hello,
                title: tr("Какой сериал учим?", "Que série vamos estudar?", "Which show are we learning?"),
                message: tr("Карта строится по сериям выбранного сериала: шаг — серия, большая "
                                + "остановка — финал сезона.",
                            "O mapa segue os episódios da série escolhida: cada passo é um episódio, "
                                + "cada paragem grande é o final de uma temporada.",
                            "The map follows the chosen show: each step is an episode, each big stop "
                                + "is a season finale.")
            ) {
                Button(tr("Выбрать сериал", "Escolher série", "Choose a show")) { showPicker = true }
                    .buttonStyle(.chunky)
                    .accessibilityIdentifier("map.choose")
            }
            .cardSurface()
            .padding(.top, 8)
        }
    }

    // MARK: - Подарки

    /// Полка подарков: открытые можно надеть на Мончика (или снять, нажав
    /// на надетый ещё раз), закрытые показывают, сколько слов до них.
    private var giftShelf: some View {
        let worn = MonchikGifts.equipped(chosen: chosenGift, words: words.words)
        return VStack(alignment: .leading, spacing: 10) {
            HintHeader(title: tr("Подарки Мончику", "Presentes do Monchik", "Monchik's presents"),
                       hint: tr("Подарки открываются за число начатых слов — во всех сериалах вместе. "
                                    + "Нажми на открытый, чтобы Мончик его надел, ещё раз — снимет.",
                                "Os presentes abrem-se com o número de palavras começadas, em todas as "
                                    + "séries. Toca num aberto para o Monchik o usar; outra vez para tirar.",
                                "Presents unlock by the number of words started across all shows. Tap an "
                                    + "open one to put it on Monchik; tap again to take it off."))
                .font(.app(.caption, weight: .heavy))
                .foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MonchikGifts.all) { gift in
                        giftTile(gift, open: gift.words <= words.words, worn: gift == worn)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .cardSurface()
    }

    private func giftTile(_ gift: MonchikGift, open: Bool, worn: Bool) -> some View {
        Button {
            guard open else { return }
            Haptics.tap()
            if worn {
                chosenGift = MonchikGifts.takenOff
            } else {
                chosenGift = gift.id
                Sounds.play(.sparkle)
            }
        } label: {
            VStack(spacing: 4) {
                Text(open ? gift.emoji : "🔒")
                    .font(.system(size: 28))
                    .frame(width: 54, height: 54)
                    .background(worn ? Theme.primary.opacity(0.18) : Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(worn ? Theme.primary : Theme.border,
                                                   lineWidth: worn ? 2.5 : Theme.stroke))
                Text(open ? gift.name : Counted.words(gift.words))
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(open ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(open ? gift.name : tr("закрыто", "fechado", "locked") + ", " + Counted.words(gift.words))
        .accessibilityValue(worn ? tr("надет", "em uso", "worn") : "")
        .accessibilityIdentifier("gift.\(gift.id)")
    }

    // MARK: - Поле

    /// Дорожка сверху вниз: первая серия наверху. Каждая строка рисует свой
    /// кусок дороги — от стыка с соседом сверху до стыка с соседом снизу, —
    /// так длинный сериал (двести серий) рисуется лениво, по мере прокрутки.
    private func board(_ path: ShowPath) -> some View {
        let nodes = path.nodes
        let reached = reachedIndex(in: nodes, path: path)
        return LazyVStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                MapRow(node: node, index: index, count: nodes.count, reached: reached,
                       isCurrent: index == reached && path.current != nil, rowHeight: rowHeight) {
                    if case .episode(let episode) = node {
                        Haptics.tap()
                        selected = episode
                    }
                }
                .id(node.id)
            }
        }
    }

    /// До какого узла дошли: текущая серия, а если всё пройдено — последний узел.
    private func reachedIndex(in nodes: [ShowPathNode], path: ShowPath) -> Int {
        guard let current = path.current else { return nodes.count - 1 }
        return nodes.firstIndex { if case .episode(let episode) = $0 { return episode.key == current.key }
                                  return false } ?? 0
    }

    // MARK: - Загрузка и действия

    private func load(scrollWith proxy: ScrollViewProxy?) {
        let progress = ProgressService(context: context)
        words = progress.journeyPosition()
        matureWords = progress.matureWordCount()
        path = StudyShow.path(in: context)
        tracked = path.flatMap { StudyShow.tracked(named: $0.name, in: context) }
        loaded = true
        guard let path else { return }
        if let current = path.current, let proxy {
            // Сразу в onAppear прокрутка теряется: поле ещё не разложено.
            DispatchQueue.main.async { proxy.scrollTo("e" + current.id, anchor: .center) }
        }
        celebrateSeasonIfNeeded(path)
    }

    private func celebrateSeasonIfNeeded(_ path: ShowPath) {
        let key = SettingsKey.showMapCelebratedSeasons + "." + path.name.lowercased()
        let stored = UserDefaults.standard.array(forKey: key) as? [Int]
        defer { UserDefaults.standard.set(path.completedSeasons, forKey: key) }
        guard let season = path.seasonToCelebrate(celebrated: stored.map(Set.init)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { celebratedSeason = season }
    }

    private func runPendingAction() {
        guard let action = pendingAction, let path else { return }
        pendingAction = nil
        switch action {
        case .study(let episode):
            if let deck = StudyShow.deck(for: episode.key, showName: path.name, in: context) {
                destination = .review(deck)
            }
        case .addCatalogWords(let episode):
            do {
                try StudyShow.installCatalogWords(for: episode.key, showName: path.name, in: context)
                Haptics.success()
            } catch {
                Log.failure(.importing, "Слова серии с карты не добавились", error)
                Haptics.failure()
            }
            load(scrollWith: nil)
        case .requestWords(let episode):
            deckRequest = EpisodeRequest(topic: "\(path.name) \(episode.code)",
                                         episode: episodeContext(episode.key))
        case .open(let episode):
            if let tracked, let context = episodeContext(episode.key) {
                destination = .episode(tracked, context)
            }
        }
    }

    private func episodeContext(_ key: EpisodeKey) -> EpisodeContext? {
        guard let tracked, let info = tracked.episodes.first(where: { $0.key == key }) else { return nil }
        return EpisodeContext(showID: tracked.tvmazeID, showName: tracked.name, episode: info)
    }
}

// MARK: - Строка карты

private struct MapRow: View {
    let node: ShowPathNode
    let index: Int
    let count: Int
    let reached: Int
    let isCurrent: Bool
    let rowHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let offset = MapGeometry.xOffset(index, width: width)
            let labelOnLeft = offset > 0
                || (offset == 0 && MapGeometry.xOffset(index + 1, width: width) > 0)
            ZStack {
                road(width: width)
                label(onLeft: labelOnLeft, width: width)
                Button(action: onTap) { nodeView }
                    .buttonStyle(.plain)
                    .disabled(!isEpisode)
                    .offset(x: offset)
                    .overlay {
                        if isCurrent {
                            MascotView(mood: .cheer, size: 50)
                                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                                .offset(x: offset, y: -40)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(accessibilityText)
                    .accessibilityIdentifier("map.\(node.id)")
            }
        }
        .frame(height: rowHeight)
    }

    private var isEpisode: Bool {
        if case .episode = node { return true }
        return false
    }

    // MARK: Дорога

    /// Кусок дороги: с верхнего стыка к центру и от центра к нижнему стыку.
    /// Стык — середина между соседями, так что куски соседних строк сходятся.
    private func road(width: CGFloat) -> some View {
        Canvas { canvas, size in
            let center = CGPoint(x: size.width / 2 + MapGeometry.xOffset(index, width: width),
                                 y: size.height / 2)
            if index > 0 {
                let x = size.width / 2
                    + (MapGeometry.xOffset(index - 1, width: width) + MapGeometry.xOffset(index, width: width)) / 2
                var top = Path()
                top.move(to: CGPoint(x: x, y: 0))
                top.addCurve(to: center, control1: CGPoint(x: x, y: size.height / 4),
                             control2: CGPoint(x: center.x, y: size.height / 4))
                stroke(top, done: index <= reached, in: &canvas)
            }
            if index < count - 1 {
                let x = size.width / 2
                    + (MapGeometry.xOffset(index, width: width) + MapGeometry.xOffset(index + 1, width: width)) / 2
                var bottom = Path()
                bottom.move(to: center)
                bottom.addCurve(to: CGPoint(x: x, y: size.height),
                                control1: CGPoint(x: center.x, y: size.height * 3 / 4),
                                control2: CGPoint(x: x, y: size.height * 3 / 4))
                stroke(bottom, done: index + 1 <= reached, in: &canvas)
            }
        }
        .accessibilityHidden(true)
    }

    private func stroke(_ path: Path, done: Bool, in canvas: inout GraphicsContext) {
        if done {
            canvas.stroke(path, with: .color(Theme.green), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        } else {
            canvas.stroke(path, with: .color(Theme.border),
                          style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [2, 16]))
        }
    }

    // MARK: Подпись

    private func label(onLeft: Bool, width: CGFloat) -> some View {
        VStack(alignment: onLeft ? .trailing : .leading, spacing: 1) {
            switch node {
            case .episode(let episode):
                Text(episode.code)
                    .font(.app(.caption, weight: .heavy))
                    .foregroundStyle(Theme.muted)
                if !episode.title.isEmpty {
                    Text(episode.title)
                        .font(.app(.subheadline, weight: .heavy))
                        .foregroundStyle(episode.isDone || isCurrent ? Theme.ink : Theme.muted)
                }
                Text(wordsLine(episode))
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            case .seasonFinale(let season, let episodes, let done):
                Text(tr("Финал сезона \(season)", "Final da temporada \(season)", "Season \(season) finale"))
                    .font(.app(.subheadline, weight: .heavy))
                    .foregroundStyle(done ? Theme.ink : Theme.muted)
                Text(done ? tr("пройден", "concluída", "done") : Counted.episodes(episodes))
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(onLeft ? .trailing : .leading)
        .frame(width: max(width / 2 - 48, 60), alignment: onLeft ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: onLeft ? .leading : .trailing)
        .padding(.horizontal, 4)
    }

    private func wordsLine(_ episode: ShowPathEpisode) -> String {
        if episode.hasDeck { return "\(episode.startedWords)/" + Counted.words(episode.totalWords) }
        if !episode.aired { return tr("ещё не вышла", "ainda não saiu", "not aired yet") }
        return episode.catalogWords
            ? tr("готовые слова", "palavras prontas", "ready words")
            : tr("слов пока нет", "ainda sem palavras", "no words yet")
    }

    // MARK: Кружок

    private var nodeView: some View {
        let big = !isEpisode
        let size: CGFloat = big ? 70 : 54
        let (fill, lip, symbol, foreground) = style
        return ZStack {
            Circle().fill(lip).offset(y: Theme.lip)
            Circle().fill(fill)
            if fill == Theme.surface {
                Circle().strokeBorder(Theme.border, lineWidth: Theme.stroke)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .heavy))
                .foregroundStyle(foreground)
            if case .episode(let episode) = node, episode.hasDeck, !episode.isDone {
                // Кольцо прогресса: сколько слов серии уже в работе.
                Circle()
                    .trim(from: 0, to: episode.fraction)
                    .stroke(Theme.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-4)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) { badges }
        .padding(.bottom, Theme.lip)
    }

    private var style: (Color, Color, String, Color) {
        switch node {
        case .seasonFinale(_, _, let done):
            return done ? (Theme.gold, Theme.orange, "trophy.fill", .white)
                        : (Theme.surface, Theme.border, "flag.checkered", Theme.muted)
        case .episode(let episode):
            if episode.isDone { return (Theme.green, Theme.green.opacity(0.6), "checkmark", .white) }
            if isCurrent { return (Theme.primary, Theme.primaryLip, "star.fill", .white) }
            if !episode.aired { return (Theme.surface, Theme.border, "lock.fill", Theme.muted) }
            return (Theme.surface, Theme.border, episode.hasDeck ? "text.book.closed" : "plus", Theme.muted)
        }
    }

    /// Отметки на кружке: просмотрена (глаз) и Recap (звезда).
    @ViewBuilder
    private var badges: some View {
        if case .episode(let episode) = node, episode.watched || episode.recapDone {
            HStack(spacing: 1) {
                if episode.watched { Image(systemName: "eye.fill") }
                if episode.recapDone { Image(systemName: "star.fill") }
            }
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(4)
            .background(Theme.purple, in: Capsule())
            .offset(x: 8, y: -4)
        }
    }

    private var accessibilityText: String {
        switch node {
        case .episode(let episode):
            let state = episode.isDone ? tr("пройдена", "concluído", "done")
                : isCurrent ? tr("сейчас", "agora", "current") : tr("впереди", "à frente", "ahead")
            return "\(episode.code) \(episode.title), \(wordsLine(episode)), \(state)"
        case .seasonFinale(let season, _, let done):
            return tr("Финал сезона \(season)", "Final da temporada \(season)", "Season \(season) finale")
                + (done ? ", " + tr("пройден", "concluída", "done") : "")
        }
    }
}

enum MapGeometry {
    /// Змейка: узлы качаются влево-вправо по синусу, как клетки на поле
    /// настольной игры, — ровная вертикаль читалась бы как список.
    static func xOffset(_ index: Int, width: CGFloat) -> CGFloat {
        let amplitude = min(width * 0.2, 96)
        return CGFloat(sin(Double(index) * .pi / 4)) * amplitude
    }
}

// MARK: - Действия с серией

enum StepAction: Equatable {
    case study(ShowPathEpisode)
    case addCatalogWords(ShowPathEpisode)
    case requestWords(ShowPathEpisode)
    case open(ShowPathEpisode)
}

enum MapDestination: Hashable {
    case review(Deck)
    case episode(TrackedShow, EpisodeContext)
}

struct EpisodeRequest: Identifiable {
    let id = UUID()
    let topic: String
    let episode: EpisodeContext?
}

/// Лист серии на карте: что с ней и что можно сделать.
private struct EpisodeStepSheet: View {
    let episode: ShowPathEpisode
    let showName: String
    let canOpenEpisode: Bool
    let act: (StepAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(showName + " · " + episode.code)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Text(episode.title.isEmpty ? episode.code : episode.title)
                    .font(.app(.title3, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            if episode.hasDeck {
                VStack(alignment: .leading, spacing: 6) {
                    ChunkyProgressBar(value: episode.fraction, tint: Theme.green, height: 12)
                    Text(episode.isDone
                         ? tr("Все слова серии в работе — серия пройдена.",
                              "Todas as palavras do episódio em curso — concluído.",
                              "Every word of the episode is in play — done.")
                         : tr("Начато \(episode.startedWords) из \(Counted.words(episode.totalWords))",
                              "Começadas \(episode.startedWords) de \(Counted.words(episode.totalWords))",
                              "Started \(episode.startedWords) of \(Counted.words(episode.totalWords))"))
                        .font(.app(.callout, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Button(tr("Учить слова серии", "Estudar as palavras", "Study the words")) { act(.study(episode)) }
                    .buttonStyle(.chunky)
                    .frame(maxWidth: .infinity)
            } else if !episode.aired {
                Text(tr("Серия ещё не вышла.", "O episódio ainda não saiu.", "This episode hasn't aired yet."))
                    .foregroundStyle(Theme.muted)
            } else if episode.catalogWords {
                Button(tr("Добавить готовые слова", "Juntar palavras prontas", "Add ready words")) {
                    act(.addCatalogWords(episode))
                }
                .buttonStyle(.chunky)
            } else {
                Button(tr("Подобрать слова к серии", "Escolher palavras", "Pick words for it")) {
                    act(.requestWords(episode))
                }
                .buttonStyle(.chunky)
            }
            if canOpenEpisode, episode.aired {
                Button(tr("Открыть серию: Recap, пересказ", "Abrir o episódio: Recap, reconto",
                          "Open the episode: Recap, retelling")) { act(.open(episode)) }
                    .buttonStyle(.chunkySecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Карточка на «Сегодня» и «Наградах»

/// Карточка карты: где ты в сериале и сколько серий пройдено. Сериал не
/// выбран — общий счёт слов и приглашение выбрать.
struct JourneyCard: View {
    let position: JourneyPosition
    var path: ShowPath?

    var body: some View {
        NavigationLink {
            JourneyMapView()
        } label: {
            HStack(spacing: 14) {
                ladder
                VStack(alignment: .leading, spacing: 6) {
                    Text(path?.name ?? tr("Путешествие", "Viagem", "Journey"))
                        .font(.app(.caption, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    if let path {
                        Text(path.current.map { $0.code + ($0.title.isEmpty ? "" : " · " + $0.title) }
                             ?? tr("Все серии пройдены", "Todos os episódios concluídos", "All episodes done"))
                            .font(.app(.headline, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        ChunkyProgressBar(value: path.total > 0 ? Double(path.doneCount) / Double(path.total) : 0,
                                          tint: Theme.green, height: 12)
                        Text(tr("Серий: \(path.doneCount) из \(path.total)", "Episódios: \(path.doneCount) de \(path.total)",
                                "Episodes: \(path.doneCount) of \(path.total)"))
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text(Counted.words(position.words))
                            .font(.app(.headline, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text(tr("Выбери сериал — карта пойдёт по его сериям",
                                "Escolhe uma série — o mapa segue os episódios",
                                "Pick a show — the map follows its episodes"))
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.muted)
            }
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journey.card")
    }

    /// Три ступеньки лесенки: следующая выше и серая, текущая — с лосем.
    private var ladder: some View {
        VStack(spacing: 4) {
            step(color: Theme.border, symbol: "lock.fill", foreground: Theme.muted)
                .offset(x: 10)
            ZStack {
                step(color: Theme.primary, symbol: nil, foreground: .white)
                MascotView(mood: .cheer, size: 34)
            }
            step(color: Theme.green, symbol: "checkmark", foreground: .white)
                .offset(x: 10)
        }
        .frame(width: 58)
        .accessibilityHidden(true)
    }

    private func step(color: Color, symbol: String?, foreground: Color) -> some View {
        ZStack {
            Circle().fill(color)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(foreground)
            }
        }
        .frame(width: 26, height: 26)
    }
}
