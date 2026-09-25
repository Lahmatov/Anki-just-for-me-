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
            .navigationTitle(tr("Награды", "Recompensas", "Rewards"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Новая цель", "Novo objetivo", "New goal"), systemImage: "plus") {
                        showNewContract = true
                    }
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
                    Text(tr("Эта неделя", "Esta semana", "This week"))
                    Spacer()
                    Text("\(week.daysStudied) " + tr("из", "de", "of") + " \(week.target)")
                        .foregroundStyle(week.isReached ? .green : .secondary)
                }
                ProgressView(value: week.fraction)
            }
            Stepper(tr("Цель: ", "Objetivo: ", "Goal: ") + Counted.days(weeklyTarget)
                        + tr(" в неделю", " por semana", " a week"),
                    value: $weeklyTarget, in: 1...7)
        } footer: {
            Text(tr("Недельная цель — в дополнение к серии дней на главном экране. "
                        + "Серия тянет вернуться завтра, а неделя прощает пропущенный "
                        + "вторник; самый опасный момент — первый пропуск — прикрывает "
                        + "заморозка.",
                    "O objetivo semanal complementa a sequência de dias no ecrã principal. "
                        + "A sequência puxa-te a voltar amanhã, a semana perdoa a terça "
                        + "falhada; o momento mais perigoso — a primeira falha — fica "
                        + "coberto por um congelamento.",
                    "The weekly goal complements the day streak on the main screen. "
                        + "The streak pulls you back tomorrow, the week forgives a missed "
                        + "Tuesday; the riskiest moment — the first gap — is covered by "
                        + "a freeze."))
        }
    }

    @ViewBuilder
    private var contractSection: some View {
        if let active {
            let progress = RewardCalculator.progress(
                contract: active, currentMatureWords: matureWords)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(active.reward).font(.app(.headline))
                    ProgressView(value: progress.fraction)
                    HStack {
                        Text("\(progress.done) " + tr("из", "de", "of") + " "
                             + Counted.words(progress.goal))
                        Spacer()
                        if let days = progress.daysLeft, days > 0 {
                            Text(Counted.days(days) + tr(" до срока", " até ao prazo", " left"))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.app(.subheadline))

                    Text(RewardCalculator.statusLine(contract: active, progress: progress))
                        .font(.app(.callout))
                        .foregroundStyle(progress.isReached ? .green : .secondary)

                    if let pace = progress.requiredPerDay {
                        Text(String(format: tr("Нужно %.1f слова в день, чтобы успеть",
                                               "São precisas %.1f palavras por dia para chegar a tempo",
                                               "You need %.1f words a day to make it"), pace))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Button(tr("Отменить цель", "Cancelar objetivo", "Cancel goal"), role: .destructive) {
                    service.delete(active)
                }
                    .font(.app(.caption))
            } header: {
                Text(tr("Текущая цель", "Objetivo atual", "Current goal"))
            } footer: {
                let matureDays = Counted.days(Int(ReviewState.matureIntervalDays))
                Text(tr("Считаются слова, дожившие до интервала в \(matureDays), и только те, "
                            + "что появились после начала цели. Просмотры не в счёт — иначе "
                            + "награду можно накликать за вечер.",
                        "Contam as palavras que chegaram a um intervalo de \(matureDays), e só "
                            + "as que surgiram depois de o objetivo começar. Visualizações não "
                            + "contam — senão a recompensa ganhava-se numa noite de cliques.",
                        "Only words that reached a \(matureDays) interval count, and only those "
                            + "added after the goal started. Views don't count — otherwise you "
                            + "could click your way to the reward in one evening."))
            }
        } else {
            Section {
                Button(tr("Завести цель", "Criar objetivo", "Set a goal"), systemImage: "target") {
                    showNewContract = true
                }
            } footer: {
                Text(tr("Придумай награду себе самому: диск с игрой, пицца, что угодно. "
                            + "Приложение честно посчитает, когда она заслужена.",
                        "Inventa uma recompensa para ti: um jogo, uma pizza, o que quiseres. "
                            + "A aplicação conta honestamente quando a mereceste.",
                        "Pick a reward for yourself: a new game, pizza, anything. "
                            + "The app will honestly count when you've earned it."))
            }
        }
    }

    @ViewBuilder
    private var achievementSection: some View {
        let current = stats
        let unlocked = AchievementCatalog.unlocked(for: current)

        Section(tr("Достижения", "Conquistas", "Achievements")
                + " — \(unlocked.count) " + tr("из", "de", "of")
                + " \(AchievementCatalog.all.count)") {
            if let next = AchievementCatalog.next(for: current) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(next.title, systemImage: next.symbol)
                        .foregroundStyle(.secondary)
                    ProgressView(value: next.progress(in: current))
                    Text(next.detail).font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
            ForEach(unlocked) { achievement in
                HStack {
                    Image(systemName: achievement.symbol)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading) {
                        Text(achievement.title)
                        Text(achievement.detail)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section(tr("Полученные награды", "Recompensas recebidas", "Rewards earned")) {
            ForEach(contracts.filter(\.isCompleted)) { contract in
                VStack(alignment: .leading, spacing: 2) {
                    Text(contract.reward)
                    Text(Counted.words(contract.goal) + " · "
                         + (contract.completedAt ?? contract.startedAt)
                            .formatted(date: .abbreviated, time: .omitted))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    if contract.hadManualAdjustments {
                        Label(tr("прогресс правился руками", "progresso corrigido à mão",
                                 "progress edited by hand"),
                              systemImage: "hand.raised")
                            .font(.app(.caption2))
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
                .symbolEffect(.bounce, options: .repeat(2))

            Text(tr("Заслужено", "Merecido", "Earned"))
                .font(.app(.largeTitle, weight: .bold))

            Text(contract.reward)
                .font(.app(.title2))
                .multilineTextAlignment(.center)

            Text(tr("В долгосрочной памяти — ", "Na memória de longo prazo — ",
                    "In long-term memory — ")
                 + Counted.words(contract.goal) + ". "
                 + tr("Это не просмотры — это реально выученные слова.",
                      "Não são visualizações — são palavras realmente aprendidas.",
                      "Not views — words you've really learned."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Следующая цель ставится сразу: награда, после которой ничего
            // не следует, гасит мотивацию вместо того, чтобы её поддержать.
            Button(action: onDone) {
                Text(tr("Получил — ставим следующую цель", "Recebido — vamos ao próximo objetivo",
                        "Got it — set the next goal"))
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
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
                    Stepper(tr("Цель: ", "Objetivo: ", "Goal: ") + Counted.words(goal),
                            value: $goal, in: 10...2000, step: 10)
                    TextField(tr("Награда: пицца, диск с игрой…", "Recompensa: pizza, um jogo…",
                                 "Reward: pizza, a new game…"), text: $reward)
                } footer: {
                    Text(tr("Сейчас в долгосрочной памяти ", "Agora na memória de longo prazo: ",
                            "In long-term memory now: ")
                         + Counted.words(currentMature) + ". "
                         + tr("Цель считается от этого числа, а не с нуля.",
                              "O objetivo conta a partir deste número, não do zero.",
                              "The goal counts from this number, not from zero."))
                }

                Section {
                    Toggle(tr("Поставить срок", "Definir prazo", "Set a deadline"), isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(tr("До", "Até", "By"), selection: $deadline,
                                   displayedComponents: .date)
                    }
                } footer: {
                    Text(tr("Со сроком приложение покажет, сколько слов в день нужно, "
                                + "чтобы успеть.",
                            "Com prazo, a aplicação mostra quantas palavras por dia são "
                                + "precisas para chegar a tempo.",
                            "With a deadline the app shows how many words a day you need "
                                + "to make it."))
                }
            }
            .navigationTitle(tr("Новая цель", "Novo objetivo", "New goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Завести", "Criar", "Create")) {
                        onCreate(goal, reward, hasDeadline ? deadline : nil)
                        dismiss()
                    }
                    .disabled(reward.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
