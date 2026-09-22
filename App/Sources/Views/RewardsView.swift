import SwiftUI
import SwiftData
import AJFMCore

/// Награды: собственные контракты вида «150 слов — и покупаю себе пиццу».
struct RewardsView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]
    @Query private var contractEntities: [RewardContractEntity]

    @AppStorage(SettingsKey.weeklyTarget) private var weeklyTarget = 5

    @State private var showNewContract = false
    @State private var celebrating: RewardContract?

    private var service: ProgressService { ProgressService(context: context) }
    private var stats: LearningStats { service.stats() }
    private var matureWords: Int { service.matureWordCount() }

    private var contracts: [RewardContract] {
        contractEntities.map(\.asContract).sorted { $0.startedAt > $1.startedAt }
    }
    private var active: RewardContract? { contracts.first { !$0.isCompleted } }

    var body: some View {
        NavigationStack {
            List {
                weekSection
                contractSection
                achievementSection
                if contracts.contains(where: \.isCompleted) {
                    historySection
                }
            }
            .navigationTitle("Награды")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Новая цель", systemImage: "plus") { showNewContract = true }
                        .disabled(active != nil)
                }
            }
            .sheet(isPresented: $showNewContract) {
                NewContractView(currentMature: matureWords) { goal, reward, deadline in
                    service.createContract(goal: goal, reward: reward, deadline: deadline)
                }
            }
            .sheet(item: $celebrating) { contract in
                RewardEarnedView(contract: contract) {
                    service.complete(contract)
                    celebrating = nil
                    showNewContract = true
                }
            }
            .onAppear(perform: checkCompletion)
            .onChange(of: matureWords) { _, _ in checkCompletion() }
        }
    }

    // MARK: - Секции

    @ViewBuilder
    private var weekSection: some View {
        let week = service.weekProgress(target: weeklyTarget)
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Эта неделя")
                    Spacer()
                    Text("\(week.daysStudied) из \(week.target)")
                        .foregroundStyle(week.isReached ? .green : .secondary)
                }
                ProgressView(value: week.fraction)
            }
            Stepper("Цель: \(weeklyTarget) дней в неделю", value: $weeklyTarget, in: 1...7)
        } footer: {
            Text("Недельная цель вместо ежедневной полоски: полоска отлично "
                 + "мотивирует ровно до первого пропуска, после которого её "
                 + "обычно бросают вместе с приложением.")
        }
    }

    @ViewBuilder
    private var contractSection: some View {
        if let active {
            let progress = RewardCalculator.progress(
                contract: active, currentMatureWords: matureWords)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(active.reward).font(.headline)
                    ProgressView(value: progress.fraction)
                    HStack {
                        Text("\(progress.done) из \(progress.goal) слов")
                        Spacer()
                        if let days = progress.daysLeft, days > 0 {
                            Text("\(days) дн до срока")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)

                    Text(RewardCalculator.statusLine(contract: active, progress: progress))
                        .font(.callout)
                        .foregroundStyle(progress.isReached ? .green : .secondary)

                    if let pace = progress.requiredPerDay {
                        Text(String(format: "Нужно %.1f слова в день, чтобы успеть", pace))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Отменить цель", role: .destructive) { service.delete(active) }
                    .font(.caption)
            } header: {
                Text("Текущая цель")
            } footer: {
                Text("Считаются слова, дожившие до интервала в "
                     + "\(Int(ReviewState.matureIntervalDays)) дней, и только те, что "
                     + "появились после начала цели. Просмотры не в счёт — иначе "
                     + "награду можно накликать за вечер.")
            }
        } else {
            Section {
                Button("Завести цель", systemImage: "target") { showNewContract = true }
            } footer: {
                Text("Придумай награду себе самому: диск с игрой, пицца, что угодно. "
                     + "Приложение честно посчитает, когда она заслужена.")
            }
        }
    }

    @ViewBuilder
    private var achievementSection: some View {
        let current = stats
        let unlocked = AchievementCatalog.unlocked(for: current)

        Section("Достижения — \(unlocked.count) из \(AchievementCatalog.all.count)") {
            if let next = AchievementCatalog.next(for: current) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(next.title, systemImage: next.symbol)
                        .foregroundStyle(.secondary)
                    ProgressView(value: next.progress(in: current))
                    Text(next.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(unlocked) { achievement in
                HStack {
                    Image(systemName: achievement.symbol)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading) {
                        Text(achievement.title)
                        Text(achievement.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("Полученные награды") {
            ForEach(contracts.filter(\.isCompleted)) { contract in
                VStack(alignment: .leading, spacing: 2) {
                    Text(contract.reward)
                    Text("\(contract.goal) слов · "
                         + (contract.completedAt ?? contract.startedAt)
                            .formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if contract.hadManualAdjustments {
                        Label("прогресс правился руками", systemImage: "hand.raised")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func checkCompletion() {
        guard let active, celebrating == nil else { return }
        let progress = RewardCalculator.progress(
            contract: active, currentMatureWords: matureWords)
        if progress.isReached { celebrating = active }
    }
}

/// Экран выдачи награды.
struct RewardEarnedView: View {
    let contract: RewardContract
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("Заслужено")
                .font(.largeTitle).bold()

            Text(contract.reward)
                .font(.title2)
                .multilineTextAlignment(.center)

            Text("\(contract.goal) слов дошли до долгосрочной памяти. "
                 + "Это не просмотры — это реально выученные слова.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Следующая цель ставится сразу: награда, после которой ничего
            // не следует, гасит мотивацию вместо того, чтобы её поддержать.
            Button("Получил — ставим следующую цель", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}

struct NewContractView: View {
    let currentMature: Int
    var onCreate: (Int, String, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal = 150
    @State private var reward = ""
    @State private var hasDeadline = false
    @State private var deadline = Date().addingTimeInterval(60 * 86_400)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Цель: \(goal) слов", value: $goal, in: 10...2000, step: 10)
                    TextField("Награда: пицца, диск с игрой…", text: $reward)
                } footer: {
                    Text("Сейчас в долгосрочной памяти \(currentMature) слов. "
                         + "Цель считается от этого числа, а не с нуля.")
                }

                Section {
                    Toggle("Поставить срок", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("До", selection: $deadline, displayedComponents: .date)
                    }
                } footer: {
                    Text("Со сроком приложение покажет, сколько слов в день нужно, "
                         + "чтобы успеть.")
                }
            }
            .navigationTitle("Новая цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Завести") {
                        onCreate(goal, reward, hasDeadline ? deadline : nil)
                        dismiss()
                    }
                    .disabled(reward.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
