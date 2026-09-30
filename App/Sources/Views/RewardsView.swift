import SwiftUI
import SwiftData
import AJFMCore

/// Награды: собственные контракты вида «150 слов — и покупаю себе пиццу».
///
/// Экран из карточек, как «Сегодня». Всё считается один раз в `refresh()`,
/// а не в `body`: статистика перебирает все повторы, и пересчёт на каждую
/// перерисовку заметно грел телефон.
struct RewardsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.weeklyTarget) private var weeklyTarget = 5

    /// Первая загрузка — без анимации. Экран вкладки создаётся заново при
    /// каждом переходе, и анимированное «пусто → данные» мигало карточками.
    @State private var loaded = false
    @State private var showNewContract = false
    @State private var celebrating: RewardContract?
    @State private var confirmCancel = false

    @State private var week: WeekProgress?
    @State private var stats: LearningStats?
    @State private var matureWords = 0
    @State private var journey: JourneyPosition?
    @State private var showPath: ShowPath?
    @State private var contracts: [RewardContract] = []

    private var service: ProgressService { ProgressService(context: context) }
    private var active: RewardContract? { contracts.first { !$0.isCompleted } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.stackSpacing) {
                    ScreenTitle(tr("Награды", "Recompensas", "Rewards"))
                    if let journey { JourneyCard(position: journey, path: showPath) }
                    contractCard
                    if let week { weekCard(week) }
                    if let stats { achievementsCard(stats) }
                    if contracts.contains(where: \.isCompleted) {
                        historyCard
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .tabRootTitle(tr("Награды", "Recompensas", "Rewards"))
            .sheet(isPresented: $showNewContract, onDismiss: refresh) {
                NewContractView(currentMature: matureWords) { goal, reward, deadline in
                    service.createContract(goal: goal, reward: reward, deadline: deadline)
                }
            }
            .sheet(item: $celebrating) { contract in
                RewardEarnedView(contract: contract) {
                    service.complete(contract)
                    celebrating = nil
                    refresh()
                    showNewContract = true
                }
            }
            .confirmationDialog(
                tr("Отменить цель?", "Cancelar o objetivo?", "Cancel the goal?"),
                isPresented: $confirmCancel, titleVisibility: .visible
            ) {
                Button(tr("Отменить цель", "Cancelar objetivo", "Cancel goal"), role: .destructive) {
                    if let active { service.delete(active) }
                    refresh()
                }
                Button(tr("Оставить", "Manter", "Keep it"), role: .cancel) {}
            } message: {
                Text(tr("Прогресс слов останется, пропадёт только сама цель с наградой.",
                        "O progresso das palavras fica; só o objetivo e a recompensa desaparecem.",
                        "Your word progress stays; only the goal and its reward go away."))
            }
            .onAppear(perform: refresh)
            .onChange(of: weeklyTarget) { _, _ in refresh() }
        }
    }

    private func refresh() {
        let service = self.service
        withAnimation(loaded ? .app : nil) {
            matureWords = service.matureWordCount()
            stats = service.stats()
            week = service.weekProgress(target: weeklyTarget)
            contracts = service.contracts()
            journey = service.journeyPosition()
            showPath = StudyShow.path(in: context)
        }
        loaded = true
        checkCompletion()
    }

    // MARK: - Цель с наградой

    @ViewBuilder
    private var contractCard: some View {
        if let active {
            let progress = RewardCalculator.progress(
                contract: active, currentMatureWords: matureWords)
            VStack(alignment: .leading, spacing: 12) {
                CardSectionHeader(title: tr("Текущая цель", "Objetivo atual", "Current goal"))
                    .padding(.top, -8)
                HStack(alignment: .center, spacing: 14) {
                    IconBadge(systemName: "gift.fill", color: Theme.gold, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.reward)
                            .font(.app(.title3))
                            .foregroundStyle(Theme.ink)
                        Text("\(progress.done) " + tr("из", "de", "of") + " "
                             + Counted.words(progress.goal))
                            .font(.app(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .contentTransition(.numericText())
                    }
                }
                ChunkyProgressBar(value: progress.fraction,
                                  tint: progress.isReached ? Theme.gold : Theme.primary)
                Text(RewardCalculator.statusLine(contract: active, progress: progress))
                    .font(.app(.callout))
                    .foregroundStyle(progress.isReached ? Theme.green : Theme.ink)
                HStack {
                    if let days = progress.daysLeft, days > 0 {
                        Label(Counted.days(days) + tr(" до срока", " até ao prazo", " left"),
                              systemImage: "calendar")
                    }
                    if let pace = progress.requiredPerDay {
                        Text(String(format: tr("%.1f слова в день", "%.1f palavras por dia",
                                               "%.1f words a day"), pace))
                    }
                }
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(Theme.muted)

                Button {
                    confirmCancel = true
                } label: {
                    Text(tr("Отменить цель", "Cancelar objetivo", "Cancel goal"))
                        .font(.app(.callout))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunkySecondary)

                let matureDays = Counted.days(Int(ReviewState.matureIntervalDays))
                Text(tr("Считаются слова, дожившие до интервала в \(matureDays), и только те, "
                            + "что появились после начала цели. Просмотры не в счёт.",
                        "Contam as palavras que chegaram a um intervalo de \(matureDays), e só "
                            + "as que surgiram depois de o objetivo começar. Visualizações não contam.",
                        "Only words that reached a \(matureDays) interval count, and only those "
                            + "added after the goal started. Views don't count."))
                    .font(.app(.caption))
                    .foregroundStyle(Theme.muted)
            }
            .cardSurface()
        } else {
            VStack(spacing: 14) {
                MascotSays(mood: .cheer,
                           text: tr("Придумай себе приз: пицца, игра, что угодно. Я честно "
                                        + "посчитаю, когда он заслужен!",
                                    "Inventa um prémio: pizza, um jogo, o que quiseres. Eu conto "
                                        + "honestamente quando o mereceres!",
                                    "Pick yourself a prize: pizza, a game, anything. I'll honestly "
                                        + "count when you've earned it!"))
                Button {
                    Haptics.tap()
                    showNewContract = true
                } label: {
                    Label(tr("Завести цель", "Criar objetivo", "Set a goal"), systemImage: "target")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky)
                .controlSize(.large)
            }
            .cardSurface()
        }
    }

    // MARK: - Неделя

    private func weekCard(_ week: WeekProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Эта неделя", "Esta semana", "This week"))
                    .font(.app(.headline))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(week.daysStudied) " + tr("из", "de", "of") + " \(week.target)")
                    .font(.app(.headline))
                    .foregroundStyle(week.isReached ? Theme.green : Theme.muted)
                    .monospacedDigit()
            }
            ChunkyProgressBar(value: week.fraction,
                              tint: week.isReached ? Theme.green : Theme.blue)
            Stepper(tr("Цель: ", "Objetivo: ", "Goal: ") + Counted.days(weeklyTarget)
                        + tr(" в неделю", " por semana", " a week"),
                    value: $weeklyTarget, in: 1...7)
                .font(.app(.callout))
            Text(tr("Серия тянет вернуться завтра, а неделя прощает пропущенный вторник.",
                    "A sequência puxa-te a voltar amanhã; a semana perdoa a terça falhada.",
                    "The streak pulls you back tomorrow; the week forgives a missed Tuesday."))
                .font(.app(.caption))
                .foregroundStyle(Theme.muted)
        }
        .cardSurface()
    }

    // MARK: - Достижения

    private func achievementsCard(_ stats: LearningStats) -> some View {
        let unlocked = AchievementCatalog.unlocked(for: stats)
        let unlockedIDs = Set(unlocked.map(\.id))
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("Достижения", "Conquistas", "Achievements"))
                    .font(.app(.headline))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(unlocked.count)/\(AchievementCatalog.all.count)")
                    .font(.app(.headline))
                    .foregroundStyle(Theme.muted)
            }

            if let next = AchievementCatalog.next(for: stats) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(next.title, systemImage: next.symbol)
                        .font(.app(.callout, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    ChunkyProgressBar(value: next.progress(in: stats), tint: Theme.purple, height: 12)
                    Text(next.detail).font(.app(.caption)).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .panel(fill: Theme.tint, lip: false)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 12) {
                ForEach(AchievementCatalog.all) { achievement in
                    let done = unlockedIDs.contains(achievement.id)
                    VStack(spacing: 6) {
                        IconBadge(systemName: achievement.symbol,
                                  color: done ? Theme.gold : Theme.border, size: 44)
                        Text(achievement.title)
                            .font(.app(.caption2, weight: .bold))
                            .foregroundStyle(done ? Theme.ink : Theme.muted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(done ? tr("получено", "obtida", "unlocked")
                                             : tr("впереди", "por obter", "locked"))
                }
            }
        }
        .cardSurface()
    }

    // MARK: - История

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Полученные награды", "Recompensas recebidas", "Rewards earned"))
                .font(.app(.headline))
                .foregroundStyle(Theme.ink)
            ForEach(contracts.filter(\.isCompleted)) { contract in
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemName: "gift.fill", color: Theme.gold, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contract.reward)
                            .font(.app(.body, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(Counted.words(contract.goal) + " · "
                             + (contract.completedAt ?? contract.startedAt)
                                .formatted(date: .abbreviated, time: .omitted))
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                        if contract.hadManualAdjustments {
                            Label(tr("прогресс правился руками", "progresso corrigido à mão",
                                     "progress edited by hand"),
                                  systemImage: "hand.raised")
                                .font(.app(.caption2))
                                .foregroundStyle(Theme.orange)
                        }
                    }
                }
            }
        }
        .cardSurface()
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
            MascotView(mood: .cheer, size: 180)

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
                .foregroundStyle(Theme.muted)
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
            .buttonStyle(.chunky)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
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
            .themedScreen()
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
