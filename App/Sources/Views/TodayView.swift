import SwiftUI
import SwiftData
import AJFMCore

/// Главный экран: что нужно повторить прямо сейчас и как идут дела.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]
    @Query private var notes: [Note]

    @Query private var reviews: [Review]

    @State private var summary: QueueSummary?
    @State private var streak: StreakStatus?
    @State private var isSessionActive = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let summary, !summary.isEmpty {
                        counters(summary)
                    } else if notes.isEmpty {
                        ContentUnavailableView(
                            "Пока пусто",
                            systemImage: "tray",
                            description: Text(
                                "Попроси Claude сделать набор карточек и импортируй его "
                                + "на вкладке «Наборы»."))
                    } else {
                        ContentUnavailableView(
                            "На сегодня всё",
                            systemImage: "checkmark.circle",
                            description: Text(
                                "Карточек по сроку нет. Это нормально — интервальное "
                                + "повторение и должно оставлять свободные дни."))
                    }
                }

                if let streak, streak.days > 0 {
                    streakSection(streak)
                }

                if let summary, summary.heldBack > 0 {
                    Section {
                        Label(
                            "\(summary.heldBack) отложено до завтра",
                            systemImage: "clock.arrow.circlepath")
                            .font(.callout)
                    } footer: {
                        Text(
                            "Сюда попадают карточки сверх дневного лимита и «братья» — "
                            + "другие карточки тех же слов, чтобы одно слово не "
                            + "встречалось за сессию по пять раз.")
                    }
                }

                StatsSection(cards: cards, notes: notes)

                Section {
                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("Графики и прогноз нагрузки", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        DifficultCardsView()
                    } label: {
                        Label("Трудные карточки", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let summary, !summary.isEmpty {
                    Button {
                        Haptics.tap()
                        isSessionActive = true
                    } label: {
                        Label("Учить \(summary.total) карточек", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Сегодня")
            .navigationDestination(isPresented: $isSessionActive) {
                ReviewSessionView(deck: nil)
            }
            .onAppear(perform: refresh)
            .onChange(of: reviews.count) { _, _ in refresh() }
            .onChange(of: isSessionActive) { _, active in
                if !active { refresh() }
            }
        }
    }

    @ViewBuilder
    private func counters(_ summary: QueueSummary) -> some View {
        HStack(alignment: .top, spacing: 0) {
            counter("Новые", summary.new, Design.color(for: .new))
            Divider().frame(height: 36)
            counter("Учатся", summary.learning, Design.color(for: .learning))
            Divider().frame(height: 36)
            counter("Повторить", summary.review, Design.color(for: .review))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func counter(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            // Цифра — главное на экране, её видно с расстояния вытянутой руки.
            Text("\(value)")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(value == 0 ? Color.secondary : color)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func refresh() {
        summary = (try? ReviewService(context: context).todayQueue())?.summary
        streak = ProgressService(context: context).streakStatus()
    }

    /// Серия дней. Исследования удержания однозначны: ежедневная серия с
    /// заморозками — одна из сильнейших причин вернуться завтра. Заморозка
    /// убирает катастрофу «один пропуск — и сто дней в ноль», из-за которой
    /// бросают приложение целиком.
    @ViewBuilder
    private func streakSection(_ streak: StreakStatus) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(streak.studiedToday ? Color.orange : Color.secondary)
                    .symbolEffect(.bounce, value: streak.days)

                VStack(alignment: .leading, spacing: 2) {
                    Text(RussianPlural.days(streak.days) + " подряд")
                        .font(.headline)
                        .contentTransition(.numericText())
                    Text(streak.isAtRisk
                         ? "Сегодня ещё не занимался"
                         : "Сегодня засчитано")
                        .font(.caption)
                        .foregroundStyle(streak.isAtRisk ? Color.orange : Color.secondary)
                }

                Spacer()

                Label("\(streak.freezesLeft)", systemImage: "snowflake")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.cyan)
                    .accessibilityLabel("Заморозок осталось: \(streak.freezesLeft)")
            }
            .padding(.vertical, 2)
        } footer: {
            Text(streak.frozenDays.isEmpty
                 ? "Пропущенный день прикроет заморозка — их две в месяц. "
                   + "Серия не обнулится от одного пропуска."
                 : "Заморозка уже прикрыла пропуск. Замороженные дни серию не рвут, "
                   + "но и в счёт не идут.")
        }
    }
}

/// Статистика, по которой видно реальный прогресс, а не количество кликов.
struct StatsSection: View {
    let cards: [Card]
    let notes: [Note]

    private var mature: Int { cards.filter(\.isMature).count }
    private var matureNotes: Int {
        Set(cards.filter(\.isMature).compactMap { $0.note?.persistentModelID }).count
    }
    private var young: Int {
        cards.filter { $0.state == .review && !$0.isMature }.count
    }
    private var fresh: Int { cards.filter { $0.state == .new }.count }

    var body: some View {
        Section {
            LabeledContent("Слов всего", value: "\(notes.count)")
            LabeledContent("В долгосрочной памяти", value: "\(matureNotes)")
            LabeledContent("Карточек зрелых", value: "\(mature)")
            LabeledContent("Карточек молодых", value: "\(young)")
            LabeledContent("Ещё не показывались", value: "\(fresh)")
        } header: {
            Text("Прогресс")
        } footer: {
            Text(
                "Слово считается выученным, когда интервал дорос до "
                + "\(Int(ReviewState.matureIntervalDays)) дней. Именно эта цифра, "
                + "а не число просмотров, пойдёт в зачёт будущих наград.")
        }
    }
}
