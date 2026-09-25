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
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Прогноз нагрузки

    @ViewBuilder
    private var forecastSection: some View {
        let days = forecast
        let peak = Forecast.peak(days)

        Section {
            if Forecast.total(days) == 0 {
                Text("Впереди пусто — все карточки либо новые, либо далеко за горизонтом.")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value("День", day.date, unit: .day),
                        y: .value("Карточек", day.dueCount),
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
                    "В среднем в день",
                    value: String(format: "%.0f", Forecast.averagePerDay(days)))
                    .font(.app(.caption))
                if let peak {
                    LabeledContent(
                        "Пик",
                        value: "\(peak.dueCount) — "
                            + peak.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.app(.caption))
                }
            }
        } header: {
            Text("Нагрузка на 30 дней")
        } footer: {
            Text("Видно заранее, если через две недели свалится горб. "
                 + "Тогда стоит временно сбавить приток новых слов.")
        }
    }

    // MARK: - Кривая роста

    @ViewBuilder
    private var growthSection: some View {
        Section {
            if snapshots.count < 2 {
                Text("Кривая появится через пару дней: она строится из ежедневных "
                     + "снимков, а история до установки приложения нигде не хранится.")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value("Дата", snapshot.date, unit: .day),
                        y: .value("Слов", snapshot.matureWords))
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
                        "Прирост за период",
                        value: "+\(max(0, last.matureWords - first.matureWords))")
                        .font(.app(.caption))
                }
            }
        } header: {
            Text("Слов в долгосрочной памяти")
        } footer: {
            Text("Та самая метрика, по которой считаются награды: "
                 + "интервал дорос до \(RussianPlural.days(Int(ReviewState.matureIntervalDays))).")
        }
    }

    // MARK: - Активность

    @ViewBuilder
    private var activitySection: some View {
        let weeks = activity
        Section {
            if weeks.allSatisfy({ $0.dueCount == 0 }) {
                Text("Повторов пока не было.")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            } else {
                Chart(weeks) { week in
                    BarMark(
                        x: .value("Неделя", week.date, unit: .weekOfYear),
                        y: .value("Повторов", week.dueCount),
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
            Text("Повторов по неделям")
        } footer: {
            Text("Считаются только честные повторы из сессий.")
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
