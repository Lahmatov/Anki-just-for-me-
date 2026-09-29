import SwiftUI
import SwiftData
import AJFMCore

/// Карта путешествия — как поле настольной игры: извилистая дорожка снизу
/// вверх, остановки — число начатых слов, сундуки — на круглых вехах, фишка
/// с Мончиком. Правила хода — `Journey` в ядре.
///
/// Дорожка идёт вверх, а не вниз: подъём читается как лесенка — чем выше,
/// тем больше выучено, и следующая остановка всегда над фишкой.
struct JourneyMapView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Где фишка стояла, когда карту открывали в прошлый раз: отсюда она
    /// и шагает до нынешней остановки.
    @AppStorage(SettingsKey.journeyLastSeenStop) private var lastSeenStop = 0

    @State private var position = Journey.position(words: 0)
    @State private var matureWords = 0
    /// Остановка, на которой сейчас нарисована фишка.
    @State private var tokenIndex = 0
    @State private var selected: JourneyStop?

    private let rowHeight: CGFloat = 104

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Design.stackSpacing) {
                    header
                    GeometryReader { geometry in
                        board(width: geometry.size.width)
                    }
                    .frame(height: rowHeight * CGFloat(Journey.stops.count))
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tr("Карта", "Mapa", "Map"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { start(proxy) }
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        let next = Journey.stops[min(position.stopIndex + 1, Journey.stops.count - 1)]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Counted.words(position.words))
                    .font(.app(.title2, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                Text(tr("выучено \(matureWords)", "aprendidas \(matureWords)", "\(matureWords) learned"))
                    .font(.app(.caption, weight: .heavy))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.green.opacity(0.2), in: Capsule())
            }
            ChunkyProgressBar(value: position.fraction, tint: Theme.green)
            Text(position.isFinished
                 ? tr("Карта пройдена целиком. Дальше — только сериалы без субтитров.",
                      "Mapa completo. Agora é ver séries sem legendas.",
                      "Map complete. Next up: shows without subtitles.")
                 : tr("До отметки «\(next.title)» — ещё \(Counted.words(position.wordsToNext))",
                      "Até «\(next.title)» — faltam \(Counted.words(position.wordsToNext))",
                      "\(Counted.words(position.wordsToNext)) to go until \(next.title)"))
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HintHeader(
                title: tr("≈ \(Counted.episodes(Journey.episodes(forWords: position.words))) из каталога",
                          "≈ \(Counted.episodes(Journey.episodes(forWords: position.words))) do catálogo",
                          "≈ \(Counted.episodes(Journey.episodes(forWords: position.words))) of the catalog"),
                hint: tr("Остановки — число начатых слов: слово считается, как только его первая "
                             + "карточка вышла из новых. В готовом наборе к серии около "
                             + "\(Journey.wordsPerEpisode) слов — отсюда «≈ серий». Выученные — "
                             + "те, что дожили до долгосрочной памяти.",
                         "As paragens são o número de palavras começadas: a palavra conta assim que "
                             + "o primeiro cartão sai dos novos. Um baralho pronto de um episódio tem "
                             + "cerca de \(Journey.wordsPerEpisode) palavras — daí o «≈ episódios». "
                             + "Aprendidas são as que chegaram à memória de longo prazo.",
                         "Stops are the number of words you've started: a word counts once its first "
                             + "card leaves New. A ready deck for an episode has about "
                             + "\(Journey.wordsPerEpisode) words — hence \"≈ episodes\". Learned "
                             + "words are the ones that reached long-term memory."))
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .cardSurface()
        .padding(.top, 8)
    }

    // MARK: - Поле

    private func board(width: CGFloat) -> some View {
        let count = Journey.stops.count
        return ZStack(alignment: .top) {
            Canvas { canvas, _ in
                drawRoad(in: &canvas, width: width)
            }
            .accessibilityHidden(true)

            // Остановки сверху вниз: финиш наверху, старт внизу.
            VStack(spacing: 0) {
                ForEach(Journey.stops.reversed()) { stop in
                    row(stop, width: width)
                        .frame(height: rowHeight)
                        .id(stop.index)
                }
            }

            MascotView(mood: .cheer, size: 58)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                .position(center(of: tokenIndex, width: width, count: count)
                          .applying(CGAffineTransform(translationX: 0, y: -40)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func row(_ stop: JourneyStop, width: CGFloat) -> some View {
        let offset = xOffset(stop.index, width: width)
        let labelOnLeft = offset > 0 || (offset == 0 && xOffset(stop.index + 1, width: width) > 0)
        let labelWidth = max(width / 2 - 52, 60)
        return ZStack {
            VStack(alignment: labelOnLeft ? .trailing : .leading, spacing: 1) {
                Text(stop.title)
                    .font(.app(.subheadline, weight: .heavy))
                    .foregroundStyle(isReached(stop) ? Theme.ink : Theme.muted)
                if stop.threshold > 0 {
                    Text("≈ " + Counted.episodes(stop.episodesEquivalent))
                        .font(.app(.caption2, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(labelOnLeft ? .trailing : .leading)
            .frame(width: labelWidth, alignment: labelOnLeft ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: labelOnLeft ? .leading : .trailing)
            .padding(.horizontal, 4)

            Button {
                Haptics.tap()
                selected = stop
            } label: {
                node(stop)
            }
            .buttonStyle(.plain)
            .offset(x: offset)
            .popover(item: popoverBinding(for: stop)) { stop in
                stopDetails(stop)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(accessibilityLabel(for: stop))
        }
    }

    /// Поповер открывается только у той остановки, на которую нажали.
    private func popoverBinding(for stop: JourneyStop) -> Binding<JourneyStop?> {
        Binding(
            get: { selected?.index == stop.index ? selected : nil },
            set: { if $0 == nil, selected?.index == stop.index { selected = nil } })
    }

    // MARK: - Кружок остановки

    private func node(_ stop: JourneyStop) -> some View {
        let reached = isReached(stop)
        let current = stop.index == position.stopIndex
        let size: CGFloat = stop.kind == .step ? 56 : 66
        let fill: Color
        let lip: Color
        switch (stop.kind, reached) {
        case (.chest, true), (.finish, true): fill = Theme.gold; lip = Theme.orange
        case (_, true): fill = current ? Theme.primary : Theme.green
            lip = current ? Theme.primaryLip : Theme.green.opacity(0.6)
        default: fill = Theme.surface; lip = Theme.border
        }
        return ZStack {
            Circle().fill(lip).offset(y: Theme.lip)
            Circle().fill(fill)
            if !reached {
                Circle().strokeBorder(Theme.border, lineWidth: Theme.stroke)
            }
            Image(systemName: symbol(for: stop, reached: reached))
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(reached ? .white : Theme.muted)
        }
        .frame(width: size, height: size)
        .padding(.bottom, Theme.lip)
    }

    private func symbol(for stop: JourneyStop, reached: Bool) -> String {
        switch stop.kind {
        case .start: return "house.fill"
        case .finish: return reached ? "trophy.fill" : "flag.checkered"
        case .chest: return reached ? "gift.fill" : "gift"
        case .step:
            if stop.index == position.stopIndex { return "star.fill" }
            return reached ? "checkmark" : "lock.fill"
        }
    }

    private func stopDetails(_ stop: JourneyStop) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stop.title).font(.app(.headline, weight: .heavy))
            if stop.threshold > 0 {
                Text(tr("≈ \(Counted.episodes(stop.episodesEquivalent)) готовых наборов",
                        "≈ \(Counted.episodes(stop.episodesEquivalent)) de baralhos prontos",
                        "≈ \(Counted.episodes(stop.episodesEquivalent)) of ready decks"))
                    .font(.app(.subheadline)).foregroundStyle(Theme.muted)
            }
            Divider()
            Text(detailText(for: stop))
                .font(.app(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    private func detailText(for stop: JourneyStop) -> String {
        if isReached(stop) {
            return stop.kind == .chest
                ? tr("Сундук открыт — ты здесь был.", "Baú aberto — já passaste por aqui.",
                     "Chest opened — you've been here.")
                : tr("Пройдено.", "Concluído.", "Done.")
        }
        let left = stop.threshold - position.words
        return tr("Осталось \(Counted.words(left)).", "Faltam \(Counted.words(left)).",
                  "\(Counted.words(left)) to go.")
    }

    private func accessibilityLabel(for stop: JourneyStop) -> String {
        let state = isReached(stop)
            ? tr("пройдено", "concluído", "done")
            : tr("впереди", "à frente", "ahead")
        return "\(stop.title), \(state)"
    }

    private func isReached(_ stop: JourneyStop) -> Bool {
        stop.index <= position.stopIndex
    }

    // MARK: - Геометрия

    /// Змейка: остановки качаются влево-вправо по синусу, как клетки на
    /// поле настольной игры, — ровная вертикаль читалась бы как список.
    private func xOffset(_ index: Int, width: CGFloat) -> CGFloat {
        let amplitude = min(width * 0.2, 96)
        return CGFloat(sin(Double(index) * .pi / 4)) * amplitude
    }

    private func center(of index: Int, width: CGFloat, count: Int) -> CGPoint {
        let row = CGFloat(count - 1 - index)
        return CGPoint(x: width / 2 + xOffset(index, width: width),
                       y: row * rowHeight + rowHeight / 2)
    }

    /// Дорога: вся — пунктиром, пройденная часть — сплошной зелёной.
    /// Рисуется один раз, без таймера: ничего не шевелится зря.
    private func drawRoad(in canvas: inout GraphicsContext, width: CGFloat) {
        let count = Journey.stops.count
        let points = (0..<count).map { center(of: $0, width: width, count: count) }

        func segment(_ from: CGPoint, _ to: CGPoint) -> Path {
            var path = Path()
            path.move(to: from)
            // Касательные вертикальны: дорожка плавно изгибается между клетками.
            let bend = (to.y - from.y) / 2
            path.addCurve(to: to, control1: CGPoint(x: from.x, y: from.y + bend),
                          control2: CGPoint(x: to.x, y: to.y - bend))
            return path
        }

        var road = Path()
        for index in 1..<count { road.addPath(segment(points[index - 1], points[index])) }
        canvas.stroke(road, with: .color(Theme.border),
                      style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [2, 16]))

        var done = Path()
        for index in stride(from: 1, through: position.stopIndex, by: 1) {
            done.addPath(segment(points[index - 1], points[index]))
        }
        if position.stopIndex + 1 < count {
            done.addPath(segment(points[position.stopIndex], points[position.stopIndex + 1])
                .trimmedPath(from: 0, to: position.fraction))
        }
        canvas.stroke(done, with: .color(Theme.green),
                      style: StrokeStyle(lineWidth: 10, lineCap: .round))
    }

    // MARK: - Ход фишки

    private func start(_ proxy: ScrollViewProxy) {
        let progress = ProgressService(context: context)
        position = progress.journeyPosition()
        matureWords = progress.matureWordCount()
        let target = position.stopIndex
        // С прошлого раза фишка могла пройти несколько клеток. Откат (слова
        // удалены) не проигрывается — фишка просто стоит, где должна.
        let from = lastSeenStop <= target ? lastSeenStop : target
        tokenIndex = from
        // Сразу в onAppear прокрутка теряется: поле ещё не разложено.
        DispatchQueue.main.async { proxy.scrollTo(from, anchor: .center) }
        lastSeenStop = target
        guard from < target, !reduceMotion else {
            tokenIndex = target
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            // Длинный путь не проигрывается целиком: пять шагов, дальше прыжок.
            let hops = Array((from + 1)...target).suffix(5)
            if let first = hops.first, first > from + 1 { tokenIndex = first - 1 }
            for index in hops {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    tokenIndex = index
                    proxy.scrollTo(index, anchor: .center)
                }
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(420))
            }
        }
    }
}

/// Карточка карты для экранов «Сегодня» и «Награды»: мини-лесенка из
/// трёх ступенек — пройденная, текущая, следующая — и полоска до следующей.
struct JourneyCard: View {
    let position: JourneyPosition

    var body: some View {
        let next = Journey.stops[min(position.stopIndex + 1, Journey.stops.count - 1)]
        NavigationLink {
            JourneyMapView()
        } label: {
            HStack(spacing: 14) {
                ladder
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Путешествие", "Viagem", "Journey"))
                        .font(.app(.caption, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                    Text(Counted.words(position.words))
                        .font(.app(.headline, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                    ChunkyProgressBar(value: position.fraction, tint: Theme.green, height: 12)
                    Text(position.isFinished
                         ? tr("Карта пройдена", "Mapa completo", "Map complete")
                         : tr("До «\(next.title)» — ещё \(position.wordsToNext)",
                              "Até «\(next.title)» — faltam \(position.wordsToNext)",
                              "\(position.wordsToNext) more to \(next.title)"))
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
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
