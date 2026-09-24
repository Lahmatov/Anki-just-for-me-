import SwiftUI
import SwiftData
import AJFMCore

/// Знакомство с приложением.
///
/// Не рекламное, а настроечное: каждый шаг что-то делает — кладёт первые слова,
/// проверяет голос, заводит цель, включает напоминание. Шаги, которые уже
/// не нужны, не показываются вовсе.
///
/// Пропустить можно в любой момент: это приложение для одного человека,
/// и держать его в мастере против воли незачем.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 20
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0

    let plan: OnboardingPlan

    @State private var index = 0
    @State private var starterInstalled = false
    @State private var starterFailed = false
    @State private var goalWords = 150
    @State private var goalReward = ""

    /// Считается один раз: читать файл на каждую перерисовку незачем.
    private var starterCount: Int { StarterDeck.wordCount() }

    private var step: OnboardingStep? {
        index < plan.steps.count ? plan.steps[index] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if plan.count > 1 {
                    ProgressView(value: Double(index + 1), total: Double(plan.count))
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.stackSpacing) {
                        if let step { content(for: step) }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    footer
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(step?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Пропустить") { finish(keepingGoal: false) }
                        .font(.callout)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Шаги

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .howItWorks: howItWorks
        case .starterDeck: starterDeck
        case .voice: voice
        case .goal: goal
        case .reminder: reminder
        }
    }

    @ViewBuilder
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Главный круг")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            loop("1", "Смотришь серию", "Как обычно, в оригинале.")
            loop("2", "Пересказываешь вслух", "Две-три минуты по-английски: о чём была, что понял.")
            loop("3", "Получаешь разбор", "Что понял верно, что переврал, и как звучал язык — "
                 + "строго по субтитрам серии.")
            loop("4", "Ошибки становятся карточками", "Слова, которых не хватило, "
                 + "и грамматика, в которой споткнулся.")
            loop("5", "Учишь их", "И следующий пересказ выходит лучше.")

            Text("Карточки можно и просто импортировать — попросив у меня набор "
                 + "по серии. Но круг выше и есть то, ради чего всё затевалось.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private func loop(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var starterDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Двадцать слов для начала")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            Text("Это лексика самого пересказа: turn out, end up, eventually, "
                 + "cliffhanger. Без неё рассказать о серии трудно, так что она "
                 + "пригодится с первого же раза.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if starterInstalled {
                Label("Добавлено — набор «Лексика для пересказа»", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button {
                    Haptics.tap()
                    if StarterDeck.install(into: context) != nil {
                        starterInstalled = true
                        starterFailed = false
                        Haptics.success()
                    } else {
                        starterFailed = true
                        Haptics.failure()
                    }
                } label: {
                    Label(starterCount > 0 ? "Добавить \(starterCount) слов" : "Добавить набор",
                          systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if starterFailed {
                    // Молчаливый отказ оставил бы человека с пустой базой
                    // и без понимания, что пошло не так.
                    Label(
                        "Набор не установился. Ничего страшного: импортируй "
                        + "examples/retelling-vocabulary.json вручную или попроси "
                        + "у Claude новый.",
                        systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private var voice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Голос звучит роботом")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            Text("Система по умолчанию ставит сжатый голос — для изучения "
                 + "произношения он плохо годится. Хороший скачивается бесплатно "
                 + "и один раз.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SpeakButton(text: "This is how it sounds right now.", label: "Послушать сейчас")

            Text(VoiceSelector.downloadHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("Приложение подхватит новый голос само.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var goal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Пообещай себе награду")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            Text("Выученным слово считается, когда интервал дорастает до "
                 + "\(Int(ReviewState.matureIntervalDays)) дней. За вечер такое "
                 + "не накликать — поэтому награда за них честная.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Stepper("Цель: \(goalWords) слов", value: $goalWords, in: 20...500, step: 10)

            TextField("Награда: пицца, диск с игрой…", text: $goalReward)
                .textFieldStyle(.roundedBorder)

            Text("Можно пропустить и завести позже на вкладке «Награды».")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var reminder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Когда напоминать")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            Text("Интервальное повторение работает, только если возвращаться "
                 + "каждый день. Пятнадцати минут хватает.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Напоминать", isOn: $reminderEnabled)

            if reminderEnabled {
                DatePicker(
                    "Время",
                    selection: Binding(
                        get: {
                            Calendar.current.date(from: DateComponents(
                                hour: reminderHour, minute: reminderMinute)) ?? Date()
                        },
                        set: { date in
                            let parts = Calendar.current.dateComponents(
                                [.hour, .minute], from: date)
                            reminderHour = parts.hour ?? 20
                            reminderMinute = parts.minute ?? 0
                        }),
                    displayedComponents: .hourAndMinute)
            }

            Text("Это локальное уведомление — работает без платного аккаунта.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    // MARK: - Навигация

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.tap()
                advance()
            } label: {
                Text(isLastStep ? "Начать" : "Дальше")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if plan.count > 1 {
                Text("\(index + 1) из \(plan.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isLastStep: Bool { index >= plan.count - 1 }

    private func advance() {
        if isLastStep {
            finish(keepingGoal: true)
        } else {
            withAnimation { index += 1 }
        }
    }

    /// - Parameter keepingGoal: нажали «Пропустить» — значит от цели
    ///   отказались, даже если награду успели напечатать.
    private func finish(keepingGoal: Bool) {
        if keepingGoal { applyGoal() }
        applyReminder()
        onboardingDone = true
        Log.info(
            .app, "Знакомство пройдено",
            detail: "шагов показано: \(index + 1) из \(plan.count)"
                + (keepingGoal ? "" : ", пропущено")) 
        dismiss()
    }

    private func applyGoal() {
        let reward = goalReward.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plan.steps.contains(.goal), !reward.isEmpty else { return }
        ProgressService(context: context).createContract(goal: goalWords, reward: reward)
    }

    private func applyReminder() {
        // Шага не было — значит напоминание уже настроено, и трогать его
        // незачем: перепланирование зря дёргает разрешения, а при отозванном
        // доступе ещё и молча выключило бы уже работающее напоминание.
        guard plan.steps.contains(.reminder) else { return }
        guard reminderEnabled else {
            NotificationService.cancelDailyReminder()
            return
        }
        let hour = reminderHour
        let minute = reminderMinute
        Task {
            guard await NotificationService.requestAuthorization() else {
                reminderEnabled = false
                return
            }
            await NotificationService.scheduleDailyReminder(hour: hour, minute: minute)
        }
    }
}
