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
                        CardSectionHeader(title: "Разбор")
                        CardLink(
                            title: "Графики и прогноз нагрузки",
                            subtitle: "Сколько карточек ждёт в ближайшие дни",
                            systemImage: "chart.bar.fill", color: .indigo
                        ) { StatsView() }
                        CardLink(
                            title: "Трудные карточки",
                            subtitle: "Слова, которые не держатся в памяти",
                            systemImage: "exclamationmark.triangle.fill", color: .orange
                        ) { DifficultCardsView() }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Сегодня")
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
                Text("На сегодня")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                // Цифра — главное на экране, её видно с вытянутой руки.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(summary.total)")
                        .font(.app(.largeTitle, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(RussianPlural.form(
                        summary.total, one: "карточка", few: "карточки", many: "карточек"))
                        .font(.app(.title3, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                chip("Новые", summary.new, Design.color(for: .new))
                chip("Учатся", summary.learning, Design.color(for: .learning))
                chip("Повторить", summary.review, Design.color(for: .review))
            }

            Button {
                Haptics.tap()
                isSessionActive = true
            } label: {
                Label("Учить", systemImage: "play.fill")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if summary.heldBack > 0 {
                Label(
                    "\(summary.heldBack) отложено до завтра — лимит дня и "
                    + "другие карточки тех же слов",
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
                Text("На сегодня всё")
                    .font(.app(.headline))
                Text("Карточек по сроку нет. Интервальное повторение и должно "
                     + "оставлять свободные дни.")
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
                Text("Начнём с первых слов")
                    .font(.app(.title2, weight: .bold))
                Text("Напиши, какую серию смотришь, — Claude подберёт слова. "
                     + "Или возьми стартовый набор для пересказа.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }

            Button {
                Haptics.tap()
                showDeckRequest = true
            } label: {
                Label("Набор через Claude", systemImage: "sparkles")
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
                Label("Стартовый набор — \(RussianPlural.words(StarterDeck.wordCount()))",
                      systemImage: "text.book.closed")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            if starterFailed {
                Label("Стартовый набор не установился — загляни в журнал событий.",
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
                    Text(RussianPlural.days(streak.days) + " подряд")
                        .font(.app(.headline))
                        .contentTransition(.numericText())
                    Text(streak.isAtRisk ? "Сегодня ещё не занимался" : "Сегодня засчитано")
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
                    .accessibilityLabel("Заморозок осталось: \(streak.freezesLeft)")
            }

            Text(streak.frozenDays.isEmpty
                 ? "Пропущенный день прикроет заморозка — их две в месяц."
                 : "Заморозка уже прикрыла пропуск. Замороженные дни серию не рвут, "
                   + "но и в счёт не идут.")
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
                    Text("Выучено")
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(RussianPlural.words(matureWords))
                        .font(.app(.title2, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Всего")
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
                    Text("До «\(contract.reward)» — \(progress.done) из "
                         + RussianPlural.words(progress.goal))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Выученным слово считается, когда интервал дорос до "
                 + RussianPlural.days(Int(ReviewState.matureIntervalDays))
                 + ". Просмотры не в счёт.")
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
