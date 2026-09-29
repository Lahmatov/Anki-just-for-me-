import SwiftUI
import SwiftData
import AJFMCore

/// Главный экран: что нужно повторить прямо сейчас и как идут дела.
///
/// Экран из карточек, а не из списка: список с цифрами справа выглядит как
/// настройки, а здесь главное одно — сколько сегодня и кнопка «учить».
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.dailyMinutesGoal) private var goalMinutes = DailyGoal.defaultMinutes

    /// Число слов, а не сами слова: @Query со всей базой перечитывался
    /// при каждом сохранении и грел телефон, а экрану нужна одна цифра.
    @State private var noteCount = 0
    @State private var studiedSeconds: TimeInterval = 0
    @State private var summary: QueueSummary?
    @State private var streak: StreakStatus?
    @State private var contract: RewardContract?
    @State private var matureWords = 0
    @State private var journey: JourneyPosition?
    @State private var isSessionActive = false
    @State private var showDeckRequest = false
    @State private var starterFailed = false

    @AppStorage(SettingsKey.dayCutoffHour) private var dayCutoffHour = AppSettings.default.dayCutoffHour
    @AppStorage(SettingsKey.goalCelebratedDay) private var goalCelebratedDay = ""
    @AppStorage(SettingsKey.celebratedStreak) private var celebratedStreak = 0
    @AppStorage(SettingsKey.journeyCelebratedStop) private var journeyCelebratedStop = -1
    @State private var celebration: CelebrationMoment?
    /// Первая загрузка — без анимации. Экран вкладки создаётся заново при
    /// каждом переходе, и анимированное «пусто → данные» мигало карточками.
    @State private var loaded = false

    struct CelebrationMoment: Equatable {
        var title: String
        var subtitle: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.stackSpacing) {
                    ScreenTitle(tr("Сегодня", "Hoje", "Today"))
                    MascotSays(mood: mood, text: greeting)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if noteCount == 0 {
                        emptyCard
                    } else if let summary, !summary.isEmpty {
                        dueCard(summary)
                    }

                    if noteCount > 0 {
                        goalCard
                        if let journey { JourneyCard(position: journey) }
                    }

                    if let streak, streak.days > 0 {
                        streakCard(streak)
                    }

                    if noteCount > 0 {
                        progressCard
                        CardSectionHeader(title: tr("Разбор", "Análise", "Insights"))
                        CardLink(
                            title: tr("Графики и прогноз нагрузки", "Gráficos e previsão",
                                      "Charts and forecast"),
                            subtitle: tr("Сколько карточек ждёт в ближайшие дни",
                                         "Quantos cartões esperam nos próximos dias",
                                         "How many cards are coming up in the next days"),
                            systemImage: "chart.bar.fill", color: .indigo
                        ) { StatsView() }
                        CardLink(
                            title: tr("Трудные карточки", "Cartões difíceis", "Difficult cards"),
                            subtitle: tr("Слова, которые не держатся в памяти",
                                         "Palavras que não ficam na memória",
                                         "Words that won't stick"),
                            systemImage: "exclamationmark.triangle.fill", color: .orange
                        ) { DifficultCardsView() }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .overlay {
                if let celebration {
                    CelebrationOverlay(title: celebration.title, subtitle: celebration.subtitle) {
                        self.celebration = nil
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            // Без этого праздник появлялся и исчезал кадром — переход не проигрывался.
            .animation(.app, value: celebration?.title)
            .tabRootTitle(tr("Сегодня", "Hoje", "Today"))
            .navigationDestination(isPresented: $isSessionActive) {
                ReviewSessionView(deck: nil)
            }
            .sheet(isPresented: $showDeckRequest, onDismiss: refresh) {
                DeckRequestView()
            }
            .onAppear(perform: refresh)
            .onChange(of: isSessionActive) { _, active in
                if !active { refresh() }
            }
        }
    }

    // MARK: - Главная карточка

    private func dueCard(_ summary: QueueSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("На сегодня", "Para hoje", "Due today"))
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.muted)
                // Цифра — главное на экране, её видно с вытянутой руки.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(summary.total)")
                        .font(.hero(48))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    Text(trForm(summary.total, ru: ("карточка", "карточки", "карточек"),
                                pt: ("cartão", "cartões"), en: ("card", "cards")))
                        .font(.app(.title3, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }

            HStack(spacing: 8) {
                chip(tr("Новые", "Novos", "New"), summary.new, Design.color(for: .new))
                chip(tr("Учатся", "A aprender", "Learning"), summary.learning,
                     Design.color(for: .learning))
                chip(tr("Повторить", "Rever", "Review"), summary.review,
                     Design.color(for: .review))
            }

            Button {
                Haptics.tap()
                isSessionActive = true
            } label: {
                Label(tr("Учить", "Estudar", "Study"), systemImage: "play.fill")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.chunky)
            .controlSize(.large)
            .accessibilityIdentifier("today.study")

            if summary.heldBack > 0 {
                Label(
                    tr("\(summary.heldBack) отложено до завтра — лимит дня и "
                        + "другие карточки тех же слов",
                       "\(summary.heldBack) adiados para amanhã — limite diário e "
                        + "outros cartões das mesmas palavras",
                       "\(summary.heldBack) held until tomorrow — the daily limit and "
                        + "other cards of the same words"),
                    systemImage: "clock.arrow.circlepath")
                    .font(.app(.caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .cardSurface()
    }

    private func chip(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.app(.title3, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(value == 0 ? Color.secondary : color)
            Text(title)
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .panel(fill: value == 0 ? Theme.tint : color.opacity(0.2), lip: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Лось

    private var mood: MascotMood {
        if noteCount == 0 { return .cards }
        if let summary, !summary.isEmpty { return .hello }
        return DailyGoal.progress(studiedSeconds: studiedSeconds, goalMinutes: goalMinutes) >= 1
            ? .cheer : .sleepy
    }

    private var greeting: String {
        if noteCount == 0 {
            return tr("Привет! Давай наберём первых слов.", "Olá! Vamos juntar as primeiras palavras.",
                      "Hi! Let's collect your first words.")
        }
        if let summary, !summary.isEmpty {
            return tr("Карточки ждут. Пара минут — и готово!", "Os cartões esperam. Uns minutos e pronto!",
                      "Cards are waiting. A few minutes and you're done!")
        }
        if DailyGoal.progress(studiedSeconds: studiedSeconds, goalMinutes: goalMinutes) >= 1 {
            return tr("Цель дня выполнена. Горжусь тобой!", "Objetivo do dia cumprido. Que orgulho!",
                      "Daily goal done. So proud of you!")
        }
        return tr("На сегодня карточек нет — и это нормально: интервалам нужны свободные дни.",
                  "Hoje não há cartões — e está tudo bem: os intervalos precisam de dias livres.",
                  "No cards today — and that's fine: spaced repetition needs free days.")
    }

    // MARK: - Цель дня

    /// Минуты за день против цели. Цель меняется тут же, меню на карточке:
    /// идти за этим в настройки — лишний шаг.
    private var goalCard: some View {
        let fraction = DailyGoal.progress(studiedSeconds: studiedSeconds, goalMinutes: goalMinutes)
        let done = DailyGoal.wholeMinutes(studiedSeconds)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Цель дня", "Objetivo do dia", "Daily goal"))
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    Text("\(done) / " + DailyGoal.format(minutes: goalMinutes))
                        .font(.app(.title3))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                }
                Spacer()
                Menu {
                    Picker(tr("Цель дня", "Objetivo do dia", "Daily goal"),
                           selection: $goalMinutes) {
                        ForEach(DailyGoal.options, id: \.self) { minutes in
                            Text(DailyGoal.format(minutes: minutes)).tag(minutes)
                        }
                    }
                } label: {
                    Label(tr("Изменить", "Mudar", "Change"), systemImage: "slider.horizontal.3")
                        .font(.app(.callout, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            ChunkyProgressBar(value: fraction, tint: fraction >= 1 ? Theme.gold : Theme.primary)
            Text(fraction >= 1
                 ? tr("Выполнено! Дальше — сверх плана.", "Cumprido! O resto é bónus.",
                      "Done! Anything more is a bonus.")
                 : tr("Считается время на карточках; больше минуты на одну не засчитывается.",
                      "Conta o tempo nos cartões; mais de um minuto por cartão não conta.",
                      "Counts time on cards; over a minute per card doesn't count."))
                .font(.app(.caption))
                .foregroundStyle(Theme.muted)
        }
        .cardSurface()
    }

    /// Пустая база — не повод для инструкции мелким шрифтом.
    /// Два действия, после которых здесь появятся слова.
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Начнём с первых слов", "Vamos às primeiras palavras",
                        "Let's start with your first words"))
                    .font(.app(.title2, weight: .bold))
                Text(tr("Напиши, какую серию смотришь, — Claude подберёт слова. "
                            + "Или возьми стартовый набор для пересказа.",
                        "Escreve que episódio estás a ver e o Claude escolhe as palavras. "
                            + "Ou começa pelo baralho inicial para recontar.",
                        "Write which episode you're watching and Claude will pick the words. "
                            + "Or take the starter deck for retelling."))
                    .font(.app(.subheadline))
                    .foregroundStyle(Theme.muted)
            }

            Button {
                Haptics.tap()
                showDeckRequest = true
            } label: {
                Label(tr("Набор через Claude", "Baralho com o Claude", "Deck with Claude"),
                      systemImage: "sparkles")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.chunky)
            .controlSize(.large)

            Button {
                Haptics.tap()
                if StarterDeck.install(into: context) != nil {
                    Haptics.success()
                    refresh()
                } else {
                    starterFailed = true
                    Haptics.failure()
                }
            } label: {
                Label(tr("Стартовый набор", "Baralho inicial", "Starter deck")
                        + " — " + Counted.words(StarterDeck.wordCount()),
                      systemImage: "text.book.closed")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.chunkySecondary)
            .controlSize(.large)
            .accessibilityIdentifier("today.starter")

            if starterFailed {
                Label(tr("Стартовый набор не установился — загляни в журнал событий.",
                         "O baralho inicial não foi instalado — vê o registo de eventos.",
                         "The starter deck didn't install — check the event log."),
                      systemImage: "exclamationmark.triangle")
                    .font(.app(.footnote))
                    .foregroundStyle(.orange)
            }
        }
        .cardSurface()
    }

    // MARK: - Серия

    /// Серия дней. Ежедневная серия с заморозками — одна из сильнейших причин
    /// вернуться завтра. Заморозка убирает катастрофу «один пропуск — и сто
    /// дней в ноль», из-за которой бросают приложение целиком.
    private func streakCard(_ streak: StreakStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(streak.studiedToday
                                     ? AnyShapeStyle(LinearGradient(
                                         colors: [.yellow, .orange, .red],
                                         startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.secondary))
                    .symbolEffect(.bounce, value: streak.days)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Counted.days(streak.days) + tr(" подряд", " seguidos", " in a row"))
                        .font(.app(.headline))
                        .contentTransition(.numericText())
                    Text(streak.isAtRisk
                         ? tr("Сегодня ещё не занимался", "Hoje ainda não estudaste",
                              "Not studied today yet")
                         : tr("Сегодня засчитано", "Hoje já conta", "Today counts"))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(streak.isAtRisk ? Theme.orange : Theme.muted)
                }

                Spacer()

                Label("\(streak.freezesLeft)", systemImage: "snowflake")
                    .font(.app(.callout, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .panel(fill: Theme.blue.opacity(0.12), border: Theme.blue, lip: false)
                    .accessibilityLabel(
                        tr("Заморозок осталось: ", "Congelamentos restantes: ", "Freezes left: ")
                        + "\(streak.freezesLeft)")
            }

            Text(streak.frozenDays.isEmpty
                 ? tr("Пропущенный день прикроет заморозка — их две в месяц.",
                      "Um dia falhado fica coberto por um congelamento — há dois por mês.",
                      "A missed day is covered by a freeze — you get two a month.")
                 : tr("Заморозка уже прикрыла пропуск. Замороженные дни серию не рвут, "
                        + "но и в счёт не идут.",
                      "Um congelamento já cobriu uma falha. Os dias congelados não quebram "
                        + "a sequência, mas também não contam.",
                      "A freeze already covered a gap. Frozen days don't break the streak, "
                        + "but they don't count either."))
                .font(.app(.caption))
                .foregroundStyle(Theme.muted)
        }
        .cardSurface()
    }

    // MARK: - Прогресс

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Выучено", "Aprendidas", "Learned"))
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Text(Counted.words(matureWords))
                        .font(.app(.title2, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("Всего", "Total", "Total"))
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Text("\(noteCount)")
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
            }

            if let contract {
                let progress = RewardCalculator.progress(
                    contract: contract, currentMatureWords: matureWords)
                VStack(alignment: .leading, spacing: 6) {
                    ChunkyProgressBar(value: progress.fraction,
                                      tint: progress.isReached ? Theme.gold : Theme.primary)
                    Text(tr("До «\(contract.reward)» — \(progress.done) из ",
                            "Até «\(contract.reward)» — \(progress.done) de ",
                            "To “\(contract.reward)” — \(progress.done) of ")
                         + Counted.words(progress.goal))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }

            Text(tr("Выученным слово считается, когда интервал дорос до ",
                    "Uma palavra conta como aprendida quando o intervalo chega a ",
                    "A word counts as learned once its interval reaches ")
                 + Counted.days(Int(ReviewState.matureIntervalDays))
                 + tr(". Просмотры не в счёт.", ". Visualizações não contam.",
                      ". Views don't count."))
                .font(.app(.caption))
                .foregroundStyle(Theme.muted)
        }
        .cardSurface()
    }

    private func refresh() {
        let goalBefore = DailyGoal.progress(studiedSeconds: studiedSeconds, goalMinutes: goalMinutes)
        withAnimation(loaded ? .app : nil) {
            noteCount = (try? context.fetchCount(FetchDescriptor<Note>())) ?? 0
            summary = (try? ReviewService(context: context).todayQueue())?.summary
            let progress = ProgressService(context: context)
            studiedSeconds = progress.studiedSecondsToday()
            streak = progress.streakStatus()
            contract = progress.activeContract
            matureWords = progress.matureWordCount()
            journey = progress.journeyPosition()
        }
        loaded = true
        celebrateIfDeserved(goalBefore: goalBefore)
    }

    // MARK: - Праздники

    /// Отметка серии важнее цели дня: цель — каждый день, а 30 дней подряд — раз в жизни.
    private func celebrateIfDeserved(goalBefore: Double) {
        let days = streak?.days ?? 0
        defer { celebratedStreak = days }
        let chest = journeyMilestone()
        if let milestone = Celebration.streakMilestone(previous: celebratedStreak, current: days) {
            celebration = CelebrationMoment(
                title: Counted.days(milestone) + tr(" подряд!", " seguidos!", " in a row!"),
                subtitle: tr("Мончик гордится. Так слова и остаются в голове — понемногу каждый день.",
                             "O Monchik está orgulhoso. É assim que as palavras ficam — um pouco todos os dias.",
                             "Monchik is proud. That's how words stick — a little every day."))
            return
        }
        if let chest {
            let stop = Journey.stops[chest]
            let episodes = Counted.episodes(stop.episodesEquivalent)
            celebration = CelebrationMoment(
                title: stop.kind == .finish
                    ? tr("\(stop.title)! Карта пройдена", "\(stop.title)! Mapa completo",
                         "\(stop.title)! Map complete")
                    : stop.title + "!",
                subtitle: tr("Это примерно \(episodes) — столько слов в готовых наборах. "
                                 + "Мончик открыл сундук на карте.",
                             "É mais ou menos \(episodes) de baralhos prontos. "
                                 + "O Monchik abriu um baú no mapa.",
                             "That's about \(episodes) worth of ready decks. "
                                 + "Monchik opened a chest on the map."))
            return
        }
        let today = Celebration.dayKey(cutoffHour: dayCutoffHour)
        let goalAfter = DailyGoal.progress(studiedSeconds: studiedSeconds, goalMinutes: goalMinutes)
        if Celebration.goalReached(progressBefore: goalBefore, progressAfter: goalAfter,
                                   celebratedDay: goalCelebratedDay, day: today) {
            goalCelebratedDay = today
            celebration = CelebrationMoment(
                title: tr("Цель дня выполнена!", "Objetivo do dia cumprido!", "Daily goal done!"),
                subtitle: DailyGoal.format(minutes: goalMinutes)
                    + tr(" английского сегодня. До завтра!", " de inglês hoje. Até amanhã!",
                         " of English today. See you tomorrow!"))
        }
    }

    /// Сундук или финиш, до которого дошли с прошлого праздника. Отметку
    /// двигаем всегда, даже если праздник уступил серии: иначе тот же
    /// сундук отпраздновали бы на следующем открытии экрана.
    private func journeyMilestone() -> Int? {
        guard let reached = journey?.stopIndex else { return nil }
        let milestone = Journey.stopToCelebrate(celebrated: journeyCelebratedStop, reached: reached)
        journeyCelebratedStop = max(journeyCelebratedStop, reached)
        return milestone
    }
}
