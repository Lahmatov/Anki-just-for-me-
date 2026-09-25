import SwiftUI
import SwiftData
import Charts
import AJFMCore

/// Графики: что придёт в ближайший месяц и как растёт выученное.
struct StatsView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]
    @Query private var reviews: [Review]
    @Query(sort: \ProgressSnapshot.date) private var snapshots: [ProgressSnapshot]

    @AppStorage(SettingsKey.dayCutoffHour) private var cutoffHour = 4

    private var forecast: [ForecastDay] {
        Forecast.upcoming(
            dueDates: cards.filter { $0.state != .new }.map(\.due),
            days: 30, cutoffHour: cutoffHour)
    }

    private var activity: [ForecastDay] {
        Forecast.weeklyActivity(reviewDates: reviews.filter(\.isHonest).map(\.timestamp))
    }

    var body: some View {
        List {
            forecastSection
            growthSection
            activitySection
        }
        .navigationTitle(tr("Статистика", "Estatísticas", "Statistics"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Прогноз нагрузки

    @ViewBuilder
    private var forecastSection: some View {
        let days = forecast
        let peak = Forecast.peak(days)

        Section {
            if Forecast.total(days) == 0 {
                Text(tr("Впереди пусто — все карточки либо новые, либо далеко за горизонтом.",
                        "Nada pela frente — os cartões são todos novos ou estão muito longe.",
                        "Nothing ahead — all cards are either new or far beyond the horizon."))
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value(tr("День", "Dia", "Day"), day.date, unit: .day),
                        y: .value(tr("Карточек", "Cartões", "Cards"), day.dueCount),
                        width: .fixed(6))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                        // Подписываем только пик: число над каждым столбиком
                        // превращает график в таблицу и мешает видеть форму.
                        .annotation(position: .top) {
                            if day.date == peak?.date, day.dueCount > 0 {
                                Text("\(day.dueCount)")
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 160)

                LabeledContent(
                    tr("В среднем в день", "Média por dia", "Average per day"),
                    value: String(format: "%.0f", Forecast.averagePerDay(days)))
                    .font(.app(.caption))
                if let peak {
                    LabeledContent(
                        tr("Пик", "Pico", "Peak"),
                        value: "\(peak.dueCount) — "
                            + peak.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.app(.caption))
                }
            }
        } header: {
            Text(tr("Нагрузка на 30 дней", "Carga para 30 dias", "Workload for 30 days"))
        } footer: {
            Text(tr("Видно заранее, если через две недели свалится горб. "
                        + "Тогда стоит временно сбавить приток новых слов.",
                    "Vê-se com antecedência se daqui a duas semanas vem um pico. "
                        + "Nesse caso, reduz por uns tempos as palavras novas.",
                    "You'll see in advance if a spike is coming in two weeks. "
                        + "Then it's worth slowing down new words for a while."))
        }
    }

    // MARK: - Кривая роста

    @ViewBuilder
    private var growthSection: some View {
        Section {
            if snapshots.count < 2 {
                Text(tr("Кривая появится через пару дней: она строится из ежедневных "
                            + "снимков, а история до установки приложения нигде не хранится.",
                        "A curva aparece daqui a uns dias: é feita de registos diários, e o "
                            + "histórico de antes da instalação não está guardado em lado nenhum.",
                        "The curve will appear in a couple of days: it's built from daily "
                            + "snapshots, and history before the app was installed isn't stored."))
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value(tr("Дата", "Data", "Date"), snapshot.date, unit: .day),
                        y: .value(tr("Слов", "Palavras", "Words"), snapshot.matureWords))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.monotone)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 160)

                if let last = snapshots.last, let first = snapshots.first {
                    LabeledContent(
                        tr("Прирост за период", "Aumento no período", "Growth over the period"),
                        value: "+\(max(0, last.matureWords - first.matureWords))")
                        .font(.app(.caption))
                }
            }
        } header: {
            Text(tr("Слов в долгосрочной памяти", "Palavras na memória de longo prazo",
                    "Words in long-term memory"))
        } footer: {
            Text(tr("Та самая метрика, по которой считаются награды: интервал дорос до ",
                    "A métrica que conta para as recompensas: o intervalo chegou a ",
                    "The metric rewards are counted by: the interval reached ")
                 + Counted.days(Int(ReviewState.matureIntervalDays)) + ".")
        }
    }

    // MARK: - Активность

    @ViewBuilder
    private var activitySection: some View {
        let weeks = activity
        Section {
            if weeks.allSatisfy({ $0.dueCount == 0 }) {
                Text(tr("Повторов пока не было.", "Ainda não houve revisões.", "No reviews yet."))
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            } else {
                Chart(weeks) { week in
                    BarMark(
                        x: .value(tr("Неделя", "Semana", "Week"), week.date, unit: .weekOfYear),
                        y: .value(tr("Повторов", "Revisões", "Reviews"), week.dueCount),
                        width: .fixed(16))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                        .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 140)
            }
        } header: {
            Text(tr("Повторов по неделям", "Revisões por semana", "Reviews per week"))
        } footer: {
            Text(tr("Считаются только честные повторы из сессий.",
                    "Só contam as revisões honestas feitas em sessões.",
                    "Only honest reviews from sessions count."))
        }
    }
}

/// Ежедневный снимок прогресса.
@MainActor
enum SnapshotService {
    static func recordIfNeeded(context: ModelContext, now: Date = Date()) {
        let existing = (try? context.fetch(FetchDescriptor<ProgressSnapshot>())) ?? []
        let today = Calendar.current.startOfDay(for: now)
        guard !existing.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }) else { return }

        let progress = ProgressService(context: context)
        context.insert(ProgressSnapshot(
            date: today,
            matureWords: progress.matureWordCount(),
            totalWords: (try? context.fetch(FetchDescriptor<Note>()))?.count ?? 0))
        try? context.save()
    }
}
