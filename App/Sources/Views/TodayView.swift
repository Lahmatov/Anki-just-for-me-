import SwiftUI
import SwiftData
import AJFMCore

/// Главный экран: что нужно повторить прямо сейчас и как идут дела.
///
/// Экран из карточек, а не из списка: список с цифрами справа выглядит как
/// настройки, а здесь главное одно — сколько сегодня и кнопка «учить».
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]
    @Query private var notes: [Note]

    @State private var summary: QueueSummary?
    @State private var streak: StreakStatus?
    @State private var contract: RewardContract?
    @State private var matureWords = 0
    @State private var isSessionActive = false
    @State private var showDeckRequest = false
    @State private var starterFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.stackSpacing) {
                    if notes.isEmpty {
                        emptyCard
                    } else if let summary, !summary.isEmpty {
                        dueCard(summary)
                    } else {
                        doneCard
                    }

                    if let streak, streak.days > 0 {
                        streakCard(streak)
                    }

                    if !notes.isEmpty {
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle(tr("Сегодня", "Hoje", "Today"))
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
            .onChange(of: notes.count) { _, _ in refresh() }
        }
    }

    // MARK: - Главная карточка

    private func dueCard(_ summary: QueueSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("На сегодня", "Para hoje", "Due today"))
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                // Цифра — главное на экране, её видно с вытянутой руки.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(summary.total)")
                        .font(.app(.largeTitle, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(trForm(summary.total, ru: ("карточка", "карточки", "карточек"),
                                pt: ("cartão", "cartões"), en: ("card", "cards")))
                        .font(.app(.title3, weight: .semibold))
                        .foregroundStyle(.secondary)
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
            .buttonStyle(.glassProminent)
            .controlSize(.large)

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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(value == 0 ? Color(.tertiarySystemFill) : color.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var doneCard: some View {
        HStack(spacing: 16) {
            IconBadge(systemName: "checkmark", color: .green, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("На сегодня всё", "Por hoje é tudo", "All done for today"))
                    .font(.app(.headline))
                Text(tr("Карточек по сроку нет. Интервальное повторение и должно "
                            + "оставлять свободные дни.",
                        "Não há cartões para hoje. A repetição espaçada deve mesmo "
                            + "deixar dias livres.",
                        "No cards are due. Spaced repetition is supposed to leave "
                            + "free days."))
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    /// Пустая база — не повод для инструкции мелким шрифтом.
    /// Два действия, после которых здесь появятся слова.
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            IconBadge(systemName: "rectangle.stack.badge.plus", size: 48)
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
                    .foregroundStyle(.secondary)
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
            .buttonStyle(.glassProminent)
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
            .buttonStyle(.glass)
            .controlSize(.large)

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
                        .foregroundStyle(streak.isAtRisk ? Color.orange : Color.secondary)
                }

                Spacer()

                Label("\(streak.freezesLeft)", systemImage: "snowflake")
                    .font(.app(.callout, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
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
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    Text(Counted.words(matureWords))
                        .font(.app(.title2, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("Всего", "Total", "Total"))
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(notes.count)")
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let contract {
                let progress = RewardCalculator.progress(
                    contract: contract, currentMatureWords: matureWords)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .tint(progress.isReached ? .green : .accentColor)
                    Text(tr("До «\(contract.reward)» — \(progress.done) из ",
                            "Até «\(contract.reward)» — \(progress.done) de ",
                            "To “\(contract.reward)” — \(progress.done) of ")
                         + Counted.words(progress.goal))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(tr("Выученным слово считается, когда интервал дорос до ",
                    "Uma palavra conta como aprendida quando o intervalo chega a ",
                    "A word counts as learned once its interval reaches ")
                 + Counted.days(Int(ReviewState.matureIntervalDays))
                 + tr(". Просмотры не в счёт.", ". Visualizações não contam.",
                      ". Views don't count."))
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    private func refresh() {
        withAnimation(.snappy) {
            summary = (try? ReviewService(context: context).todayQueue())?.summary
            let progress = ProgressService(context: context)
            streak = progress.streakStatus()
            contract = progress.activeContract
            matureWords = progress.matureWordCount()
        }
    }
}
