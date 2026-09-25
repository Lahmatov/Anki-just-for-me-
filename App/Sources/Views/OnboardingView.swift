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
    @AppStorage(SettingsKey.appLanguage) private var storedLanguage: String?
    @AppStorage(SettingsKey.englishLevel) private var storedLevel: String?

    let plan: OnboardingPlan

    @State private var index = 0
    @State private var starterInstalled = false
    @State private var starterFailed = false
    @State private var goalWords = 150
    @State private var goalReward = ""
    @State private var showPlacementTest = false

    /// Считается один раз: читать файл на каждую перерисовку незачем.
    private var starterCount: Int { StarterDeck.wordCount() }

    private var step: OnboardingStep? {
        index < plan.steps.count ? plan.steps[index] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if plan.count > 1 {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: Double(index + 1), total: Double(plan.count))
                        Text("\(index + 1) " + tr("из", "de", "of") + " \(plan.count)")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
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
                    Button(CommonText.skip) { finish(keepingGoal: false) }
                        .font(.app(.callout))
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Шаги

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        switch step {
        case .language: language
        case .howItWorks: howItWorks
        case .level: level
        case .starterDeck: starterDeck
        case .voice: voice
        case .goal: goal
        case .reminder: reminder
        }
    }

    /// Выбранный язык, а пока не выбран — системный.
    private var currentLanguage: AppLanguage {
        storedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? AppSettings.language
    }

    @ViewBuilder
    private var language: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Язык приложения", "Idioma da aplicação", "App language"))
                .font(.app(.title2, weight: .semibold))
            Text(tr("На нём же будут переводы в карточках и разборы пересказов. "
                        + "Поменять можно в любой момент в настройках.",
                    "É também o idioma das traduções nos cartões e das análises dos "
                        + "recontos. Podes mudá-lo a qualquer momento nas definições.",
                    "Card translations and retelling reviews will be in it too. "
                        + "You can change it any time in Settings."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) { AppSettings.setLanguage(option) }
                    } label: {
                        HStack {
                            Text(option.nativeName)
                                .font(.app(.body, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if option == currentLanguage {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(option == currentLanguage
                                      ? Color.accentColor.opacity(0.12)
                                      : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.snappy, value: currentLanguage)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var level: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Какой у тебя уровень", "Qual é o teu nível", "What's your level"))
                .font(.app(.title2, weight: .semibold))
            Text(tr("От него зависит, какие слова подбирать: слишком простые "
                        + "скучны, слишком редкие не пригодятся. Тест — три минуты, "
                        + "слово за словом: знаешь или нет.",
                    "Dele depende que palavras escolher: as demasiado fáceis aborrecem, "
                        + "as demasiado raras não servem. O teste leva três minutos, "
                        + "palavra a palavra: sabes ou não.",
                    "It decides which words to pick: too easy is boring, too rare is "
                        + "useless. The test takes three minutes, word by word: "
                        + "do you know it or not."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            if let chosen = storedLevel.flatMap(CEFRLevel.init(rawValue:)) {
                Label(tr("Уровень", "Nível", "Level") + " \(chosen.rawValue)",
                      systemImage: "checkmark.circle")
                    .font(.app(.headline))
                    .foregroundStyle(.green)
            }

            Button {
                Haptics.tap()
                showPlacementTest = true
            } label: {
                Label(storedLevel == nil
                      ? tr("Пройти тест", "Fazer o teste", "Take the test")
                      : tr("Пройти ещё раз", "Repetir", "Take it again"),
                      systemImage: "text.magnifyingglass")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Picker(tr("Или выбрать самому", "Ou escolher eu", "Or pick it myself"),
                   selection: Binding(
                get: { storedLevel.flatMap(CEFRLevel.init(rawValue:)) },
                set: { storedLevel = $0?.rawValue })
            ) {
                Text(CommonText.notSelected).tag(CEFRLevel?.none)
                ForEach(CEFRLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(CEFRLevel?.some(level))
                }
            }
            .font(.app(.callout))
        }
        .cardSurface()
        .sheet(isPresented: $showPlacementTest) {
            PlacementTestView { storedLevel = $0.rawValue }
        }
    }

    @ViewBuilder
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("Главный круг", "O ciclo principal", "The main loop"))
                .font(.app(.title2, weight: .semibold))

            loop("1", tr("Смотришь серию", "Vês um episódio", "You watch an episode"),
                 tr("Как обычно, в оригинале.", "Como sempre, na versão original.",
                    "As usual, in the original."))
            loop("2", tr("Пересказываешь вслух", "Recontas em voz alta", "You retell it out loud"),
                 tr("Две-три минуты по-английски: о чём была, что понял.",
                    "Dois ou três minutos em inglês: de que tratou, o que percebeste.",
                    "Two or three minutes in English: what it was about, what you got."))
            loop("3", tr("Получаешь разбор", "Recebes uma análise", "You get a review"),
                 tr("Что понял верно, что переврал и как звучал язык — строго по субтитрам серии.",
                    "O que percebeste bem, o que trocaste e como soou a língua — "
                        + "sempre segundo as legendas.",
                    "What you got right, what you mixed up and how your English sounded — "
                        + "strictly by the subtitles."))
            loop("4", tr("Ошибки становятся карточками", "Os erros viram cartões",
                         "Mistakes become cards"),
                 tr("Слова, которых не хватило, и грамматика, в которой споткнулся.",
                    "As palavras que faltaram e a gramática em que tropeçaste.",
                    "The words you were missing and the grammar you tripped over."))
            loop("5", tr("Учишь их", "Estudas", "You learn them"),
                 tr("И следующий пересказ выходит лучше.", "E o próximo reconto sai melhor.",
                    "And the next retelling comes out better."))

            Text(tr("Слова можно и просто попросить у Claude — кнопкой «Набор через Claude». "
                        + "Но круг выше и есть то, ради чего всё затевалось.",
                    "Também podes simplesmente pedir palavras ao Claude — no botão "
                        + "«Baralho com o Claude». Mas o ciclo acima é a razão de tudo isto.",
                    "You can also just ask Claude for words — with the “Deck with Claude” "
                        + "button. But the loop above is what this is all about."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private func loop(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.app(.footnote, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.headline))
                Text(detail).font(.app(.callout)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var starterDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Слова для начала", "Palavras para começar", "Words to start with"))
                .font(.app(.title2, weight: .semibold))

            Text(tr("Это лексика самого пересказа: turn out, end up, eventually, "
                        + "cliffhanger. Без неё рассказать о серии трудно, так что она "
                        + "пригодится с первого же раза.",
                    "É o vocabulário do próprio reconto: turn out, end up, eventually, "
                        + "cliffhanger. Sem ele é difícil contar um episódio, por isso "
                        + "serve logo da primeira vez.",
                    "This is the vocabulary of retelling itself: turn out, end up, "
                        + "eventually, cliffhanger. It's hard to retell an episode "
                        + "without it, so it helps from the very first time."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            if starterInstalled {
                Label(tr("Добавлено — стартовый набор уже в «Наборах»",
                         "Adicionado — o baralho inicial já está em «Baralhos»",
                         "Added — the starter deck is in Decks"),
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.app(.callout))
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
                    Label(tr("Добавить", "Adicionar", "Add") + " "
                            + (starterCount > 0
                               ? Counted.words(starterCount)
                               : tr("набор", "o baralho", "the deck")),
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
                        tr("Набор не установился. Ничего страшного: попроси слова у Claude "
                                + "кнопкой «Набор через Claude» на вкладке «Наборы».",
                           "O baralho não foi instalado. Não faz mal: pede palavras ao Claude "
                                + "no botão «Baralho com o Claude», no separador «Baralhos».",
                           "The deck didn't install. No problem: ask Claude for words with "
                                + "the “Deck with Claude” button on the Decks tab."),
                        systemImage: "exclamationmark.triangle")
                        .font(.app(.footnote))
                        .foregroundStyle(.orange)
                }
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private var voice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Голос звучит роботом", "A voz soa robótica", "The voice sounds robotic"))
                .font(.app(.title2, weight: .semibold))

            Text(tr("Система по умолчанию ставит сжатый голос — для изучения "
                        + "произношения он плохо годится. Хороший скачивается бесплатно "
                        + "и один раз.",
                    "Por omissão, o sistema usa uma voz comprimida — não serve bem para "
                        + "aprender pronúncia. Uma boa descarrega-se de graça, uma vez só.",
                    "By default the system uses a compressed voice — not great for "
                        + "learning pronunciation. A good one is a free, one-time download."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            SpeakButton(text: "This is how it sounds right now.",
                        label: tr("Послушать сейчас", "Ouvir agora", "Listen now"))

            Text(VoiceSelector.downloadHint)
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text(tr("Приложение подхватит новый голос само.",
                    "A aplicação passa a usar a nova voz sozinha.",
                    "The app will pick up the new voice by itself."))
                .font(.app(.footnote))
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var goal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Пообещай себе награду", "Promete a ti mesmo uma recompensa",
                    "Promise yourself a reward"))
                .font(.app(.title2, weight: .semibold))

            let matureDays = Counted.days(Int(ReviewState.matureIntervalDays))
            Text(tr("Выученным слово считается, когда интервал дорастает до \(matureDays). "
                        + "За вечер такое не накликать — поэтому награда за них честная.",
                    "Uma palavra conta como aprendida quando o intervalo chega a "
                        + "\(matureDays). Não se consegue isso numa noite — por isso "
                        + "a recompensa é honesta.",
                    "A word counts as learned once its interval reaches \(matureDays). "
                        + "You can't click through that in an evening — so the reward "
                        + "is honest."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            Stepper(tr("Цель: ", "Objetivo: ", "Goal: ") + Counted.words(goalWords),
                    value: $goalWords, in: 20...500, step: 10)

            TextField(tr("Награда: пицца, диск с игрой…", "Recompensa: pizza, um jogo…",
                         "Reward: pizza, a new game…"), text: $goalReward)
                .textFieldStyle(.roundedBorder)

            Text(tr("Можно пропустить и завести позже на вкладке «Награды».",
                    "Podes saltar e criá-lo depois no separador «Recompensas».",
                    "You can skip this and set it up later on the Rewards tab."))
                .font(.app(.footnote))
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var reminder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Когда напоминать", "Quando lembrar", "When to remind you"))
                .font(.app(.title2, weight: .semibold))

            Text(tr("Интервальное повторение работает, только если возвращаться "
                        + "каждый день. Пятнадцати минут хватает.",
                    "A repetição espaçada só funciona se voltares todos os dias. "
                        + "Quinze minutos chegam.",
                    "Spaced repetition only works if you come back every day. "
                        + "Fifteen minutes is enough."))
                .font(.app(.callout))
                .foregroundStyle(.secondary)

            Toggle(tr("Напоминать", "Lembrar", "Remind me"), isOn: $reminderEnabled)

            if reminderEnabled {
                DatePicker(
                    tr("Время", "Hora", "Time"),
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

            Text(tr("Это локальное уведомление — работает без платного аккаунта.",
                    "É uma notificação local — funciona sem conta paga.",
                    "It's a local notification — no paid account needed."))
                .font(.app(.footnote))
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    // MARK: - Навигация

    private var footer: some View {
        Button {
            Haptics.tap()
            advance()
        } label: {
            Text(isLastStep ? tr("Начать", "Começar", "Start") : CommonText.next)
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private var isLastStep: Bool { index >= plan.count - 1 }

    private func advance() {
        // Нажал «Дальше» на шаге языка, ничего не трогая, — согласился
        // с системным. Запоминаем, чтобы не спрашивать снова.
        if step == .language, storedLanguage == nil {
            AppSettings.setLanguage(currentLanguage)
        }
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
