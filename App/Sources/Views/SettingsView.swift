import SwiftUI
import SwiftData
import AJFMCore

struct SettingsView: View {
    @AppStorage(SettingsKey.newPerDay) private var newPerDay = AppSettings.default.newPerDay
    @AppStorage(SettingsKey.reviewsPerDay) private var reviewsPerDay =
        AppSettings.default.reviewsPerDay
    @AppStorage(SettingsKey.burySiblings) private var burySiblings =
        AppSettings.default.burySiblings
    @AppStorage(SettingsKey.dayCutoffHour) private var dayCutoffHour =
        AppSettings.default.dayCutoffHour
    @AppStorage(SettingsKey.desiredRetention) private var desiredRetention =
        AppSettings.default.desiredRetention

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true
    @AppStorage(SettingsKey.fontStyle) private var fontStyle = AppFont.manrope.rawValue
    @AppStorage(SettingsKey.englishLevel) private var storedLevel: String?
    @State private var showPlacementTest = false
    @AppStorage(SettingsKey.claudeModel) private var claudeModel = ClaudeModel.opus5.id
    @AppStorage(SettingsKey.monthlyBudget) private var monthlyBudget = 10.0
    @State private var apiKey = ""
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 20
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0

    @Environment(\.modelContext) private var context
    @State private var onboarding: OnboardingPlan?

    private var speech: SpeechService { SpeechService.shared }

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                levelSection
                appearanceSection
                loadSection
                speechSection
                claudeSection
                reminderSection
                aboutSection
            }
            .navigationTitle(tr("Настройки", "Definições", "Settings"))
            .onAppear { apiKey = Keychain.get(Keychain.claudeAPIKey) ?? "" }
            .sheet(item: $onboarding) { plan in
                OnboardingView(plan: plan)
            }
            .onChange(of: reminderEnabled) { _, enabled in
                Task { await applyReminder(enabled: enabled) }
            }
        }
    }

    // MARK: - Язык, уровень, оформление

    private var languageSection: some View {
        Section {
            Picker(tr("Язык", "Idioma", "Language"), selection: Binding(
                get: { Loc.language },
                set: { AppSettings.setLanguage($0) })
            ) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName).tag(language)
                }
            }
        } footer: {
            Text(tr("На нём же переводы в новых наборах и разборы пересказов. "
                        + "Уже добавленные слова остаются как есть.",
                    "É também o idioma das traduções nos novos baralhos e das análises "
                        + "dos recontos. As palavras já adicionadas ficam como estão.",
                    "New decks and retelling reviews will use it too. "
                        + "Words you already have stay as they are."))
        }
    }

    private var levelSection: some View {
        Section {
            Picker(tr("Уровень английского", "Nível de inglês", "English level"),
                   selection: Binding(
                    get: { storedLevel.flatMap(CEFRLevel.init(rawValue:)) },
                    set: { storedLevel = $0?.rawValue })
            ) {
                Text(CommonText.notSelected).tag(CEFRLevel?.none)
                ForEach(CEFRLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(CEFRLevel?.some(level))
                }
            }
            Button(tr("Пройти тест словаря", "Fazer o teste de vocabulário",
                      "Take the vocabulary test"),
                   systemImage: "text.magnifyingglass") {
                showPlacementTest = true
            }
        } footer: {
            Text(tr("По уровню подбираются слова в наборах от Claude — на ступень выше, "
                        + "чтобы не было ни скучно, ни бесполезно редко.",
                    "O nível decide as palavras dos baralhos do Claude — um degrau acima, "
                        + "nem aborrecidas nem inutilmente raras.",
                    "Your level decides the words in Claude's decks — one step above, "
                        + "neither boring nor uselessly rare."))
        }
        .sheet(isPresented: $showPlacementTest) {
            PlacementTestView { storedLevel = $0.rawValue }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(tr("Шрифт", "Tipo de letra", "Font"), selection: Binding(
                get: { AppFont(rawValue: fontStyle) ?? .manrope },
                set: { choice in
                    // Заголовки навигации — UIKit: им шрифт нужно отдать до того,
                    // как экраны перестроятся с новым выбором.
                    choice.applyToNavigationBars()
                    fontStyle = choice.rawValue
                })
            ) {
                ForEach(AppFont.allCases) { font in
                    Text(font.title)
                        .font(font.font(.body, weight: nil))
                        .tag(font)
                }
            }
            .pickerStyle(.navigationLink)

            VStack(alignment: .leading, spacing: 6) {
                Text("Turn out · " + tr("оказаться", "revelar-se", "prove to be"))
                    .font(.app(.title3, weight: .semibold))
                Text("It turned out he was right all along.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text(tr("Оформление", "Aspeto", "Appearance"))
        }
    }

    // MARK: - Учёба

    @ViewBuilder
    private var loadSection: some View {
        Section {
            Stepper(tr("Новых в день: ", "Novos por dia: ", "New per day: ") + "\(newPerDay)",
                    value: $newPerDay, in: 0...200, step: 5)
            Stepper(tr("Повторов в день: ", "Revisões por dia: ", "Reviews per day: ")
                        + "\(reviewsPerDay)",
                    value: $reviewsPerDay, in: 10...999, step: 10)
        } header: {
            Text(tr("Нагрузка", "Carga", "Workload"))
        } footer: {
            Text(tr("Лимиты спасают после пропуска: вместо очереди из четырёхсот "
                        + "карточек получишь обычный день, а долг разойдётся постепенно.",
                    "Os limites salvam-te depois de uma falha: em vez de uma fila de "
                        + "quatrocentos cartões, tens um dia normal e a dívida dilui-se aos poucos.",
                    "Limits save you after a break: instead of a queue of four hundred "
                        + "cards you get a normal day, and the backlog clears gradually."))
        }

        Section {
            Toggle(tr("Разносить карточки одного слова", "Separar cartões da mesma palavra",
                      "Spread out cards of the same word"),
                   isOn: $burySiblings)
        } footer: {
            Text(tr("Показав одну карточку слова, остальные откладываем на завтра. "
                        + "Иначе одно слово встретится за сессию пять раз, и ты решишь, "
                        + "что выучил его, хотя просто запомнил на минуту.",
                    "Depois de mostrar um cartão de uma palavra, os outros ficam para "
                        + "amanhã. Senão a mesma palavra aparece cinco vezes na sessão e "
                        + "achas que a aprendeste, quando só a fixaste por um minuto.",
                    "After one card of a word, the others wait until tomorrow. Otherwise "
                        + "the same word shows up five times a session and you'll think "
                        + "you learned it, when you only remembered it for a minute."))
        }

        Section {
            Picker(tr("День кончается в", "O dia acaba às", "The day ends at"),
                   selection: $dayCutoffHour) {
                ForEach(0...8, id: \.self) { hour in
                    Text("\(hour):00").tag(hour)
                }
            }
        } footer: {
            Text(tr("Занятие в час ночи засчитывается во вчерашний день — "
                        + "иначе ночные сессии рвут счёт дней на ровном месте.",
                    "Estudar à uma da manhã conta para o dia anterior — senão as "
                        + "sessões noturnas quebram a contagem de dias sem razão.",
                    "Studying at 1 a.m. counts toward the previous day — otherwise "
                        + "late-night sessions would break your streak for nothing."))
        }

        Section {
            Picker(tr("Целевое удержание", "Retenção desejada", "Target retention"),
                   selection: $desiredRetention) {
                Text(tr("70% — реже повторять", "70% — rever menos", "70% — fewer reviews"))
                    .tag(0.7)
                Text("80%").tag(0.8)
                Text(tr("90% — по умолчанию", "90% — predefinido", "90% — default")).tag(0.9)
                Text(tr("95% — помнить надёжнее", "95% — lembrar melhor",
                        "95% — remember more reliably")).tag(0.95)
            }
        } header: {
            Text("FSRS")
        } footer: {
            Text(tr("Какую долю карточек ты хочешь помнить в момент показа. "
                        + "Выше планка — заметно больше повторений ради небольшого "
                        + "выигрыша. Работает только для FSRS.",
                    "Que parte dos cartões queres lembrar no momento em que aparecem. "
                        + "Uma fasquia mais alta custa muito mais revisões por um ganho "
                        + "pequeno. Só funciona com o FSRS.",
                    "What share of cards you want to remember when they come up. "
                        + "A higher bar costs many more reviews for a small gain. "
                        + "Only affects FSRS."))
        }
    }

    // MARK: - Звук и Claude

    private var speechSection: some View {
        Section {
            Toggle(tr("Озвучивать автоматически", "Ler em voz alta automaticamente",
                      "Speak automatically"),
                   isOn: $autoSpeak)
            if let voice = speech.voiceName {
                LabeledContent(tr("Голос", "Voz", "Voice"), value: voice)
            }
            if speech.shouldSuggestBetterVoice {
                Text(VoiceSelector.downloadHint)
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(tr("Звук", "Som", "Sound"))
        } footer: {
            Text(tr("Карточка на слух озвучивается сразу при показе, а слово "
                        + "проговаривается после ответа.",
                    "O cartão de audição é lido logo ao aparecer, e a palavra é "
                        + "dita depois da resposta.",
                    "Listening cards play as soon as they appear, and the word "
                        + "is spoken after you answer."))
        }
    }

    private var claudeSection: some View {
        Section {
            SecureField(tr("Ключ API", "Chave da API", "API key"), text: $apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: apiKey) { _, value in
                    Keychain.set(value.trimmingCharacters(in: .whitespaces),
                                 for: Keychain.claudeAPIKey)
                }
            Picker(tr("Модель", "Modelo", "Model"), selection: $claudeModel) {
                ForEach(ClaudeModel.all, id: \.id) { pricing in
                    Text(pricing.title + " — " + ClaudeModel.summary(for: pricing))
                        .tag(pricing.id)
                }
            }
            Stepper(tr("Лимит в месяц: ", "Limite mensal: ", "Monthly limit: ")
                        + "$\(Int(monthlyBudget))",
                    value: $monthlyBudget, in: 1...100, step: 1)
        } header: {
            Text("Claude")
        } footer: {
            Text(tr("Наборы по запросу и разборы пересказов. Ключ хранится в Keychain и "
                        + "никуда, кроме Anthropic, не уходит. Лимит нужен не ради экономии, "
                        + "а чтобы ошибка в коде не съела бюджет молча.",
                    "Baralhos a pedido e análises de recontos. A chave fica no Keychain e "
                        + "só vai para a Anthropic. O limite não é para poupar — é para que "
                        + "um erro no código não gaste o orçamento às escondidas.",
                    "Decks on request and retelling reviews. The key lives in the Keychain "
                        + "and goes nowhere but Anthropic. The limit isn't about saving — "
                        + "it's so a bug can't quietly eat the budget."))
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(tr("Напоминание", "Lembrete", "Reminder"), isOn: $reminderEnabled)
            if reminderEnabled {
                DatePicker(
                    tr("Время", "Hora", "Time"),
                    selection: Binding(
                        get: { reminderDate },
                        set: { setReminderDate($0) }),
                    displayedComponents: .hourAndMinute)
            }
        } header: {
            Text(tr("Напоминания", "Lembretes", "Reminders"))
        } footer: {
            Text(tr("Локальное уведомление — работает без платного аккаунта Apple.",
                    "Notificação local — funciona sem conta paga da Apple.",
                    "A local notification — no paid Apple account needed."))
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                onboarding = OnboardingPlanBuilder.make(context: context)
            } label: {
                Label(tr("Показать знакомство", "Mostrar a introdução", "Show the intro"),
                      systemImage: "sparkles")
            }
            NavigationLink {
                LogView()
            } label: {
                Label(tr("Журнал событий", "Registo de eventos", "Event log"),
                      systemImage: "text.alignleft")
            }
        } footer: {
            Text(tr("Что происходило внутри приложения. Если что-то повело себя "
                        + "странно — журнал можно переслать одним нажатием, это "
                        + "быстрее любых описаний.",
                    "O que aconteceu dentro da aplicação. Se algo se portou de forma "
                        + "estranha, o registo envia-se com um toque — é mais rápido "
                        + "do que qualquer descrição.",
                    "What happened inside the app. If something behaved oddly, the log "
                        + "can be shared with one tap — faster than any description."))
        }
    }

    private var reminderDate: Date {
        Calendar.current.date(
            from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
    }

    private func setReminderDate(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderHour = components.hour ?? 20
        reminderMinute = components.minute ?? 0
        Task { await applyReminder(enabled: reminderEnabled) }
    }

    private func applyReminder(enabled: Bool) async {
        guard enabled else {
            NotificationService.cancelDailyReminder()
            return
        }
        guard await NotificationService.requestAuthorization() else {
            reminderEnabled = false
            return
        }
        await NotificationService.scheduleDailyReminder(
            hour: reminderHour, minute: reminderMinute)
    }
}
