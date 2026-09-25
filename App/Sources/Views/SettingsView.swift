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
                levelSection
                appearanceSection

                Section {
                    Stepper("Новых в день: \(newPerDay)", value: $newPerDay, in: 0...200, step: 5)
                    Stepper(
                        "Повторов в день: \(reviewsPerDay)",
                        value: $reviewsPerDay, in: 10...999, step: 10)
                } header: {
                    Text("Нагрузка")
                } footer: {
                    Text(
                        "Лимиты спасают после пропуска: вместо очереди из четырёхсот "
                        + "карточек получишь обычный день, а долг разойдётся постепенно.")
                }

                Section {
                    Toggle("Разносить карточки одного слова", isOn: $burySiblings)
                } footer: {
                    Text(
                        "Показав одну карточку слова, остальные откладываем на завтра. "
                        + "Иначе одно слово встретится за сессию пять раз, и ты решишь, "
                        + "что выучил его, хотя просто запомнил на минуту.")
                }

                Section {
                    Picker("День кончается в", selection: $dayCutoffHour) {
                        ForEach(0...8, id: \.self) { hour in
                            Text("\(hour):00").tag(hour)
                        }
                    }
                } footer: {
                    Text(
                        "Занятие в час ночи засчитывается во вчерашний день — "
                        + "иначе ночные сессии рвут счёт дней на ровном месте.")
                }

                Section {
                    Picker("Целевое удержание", selection: $desiredRetention) {
                        Text("70% — реже повторять").tag(0.7)
                        Text("80%").tag(0.8)
                        Text("90% — по умолчанию").tag(0.9)
                        Text("95% — помнить надёжнее").tag(0.95)
                    }
                } header: {
                    Text("FSRS")
                } footer: {
                    Text(
                        "Какую долю карточек ты хочешь помнить в момент показа. "
                        + "Выше планка — заметно больше повторений ради небольшого "
                        + "выигрыша. Работает только для FSRS.")
                }

                Section {
                    Toggle("Озвучивать автоматически", isOn: $autoSpeak)
                    if let voice = speech.voiceName {
                        LabeledContent("Голос", value: voice)
                    }
                    if speech.shouldSuggestBetterVoice {
                        Text(VoiceSelector.downloadHint)
                            .font(.app(.caption))
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Звук")
                } footer: {
                    Text(
                        "Карточка на слух озвучивается сразу при показе, а слово "
                        + "проговаривается после ответа.")
                }

                Section {
                    SecureField("Ключ API", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiKey) { _, value in
                            Keychain.set(value.trimmingCharacters(in: .whitespaces),
                                         for: Keychain.claudeAPIKey)
                        }
                    Picker("Модель", selection: $claudeModel) {
                        ForEach(ClaudeModel.all, id: \.id) { pricing in
                            Text(pricing.title).tag(pricing.id)
                        }
                    }
                    Stepper(
                        "Лимит в месяц: $\(Int(monthlyBudget))",
                        value: $monthlyBudget, in: 1...100, step: 1)
                } header: {
                    Text("Разбор пересказов")
                } footer: {
                    Text("Ключ хранится в Keychain и никуда, кроме Anthropic, не уходит. "
                         + "Лимит нужен не ради экономии — бюджета хватает с запасом, — "
                         + "а чтобы ошибка в коде не съела его молча.")
                }

                Section {
                    Toggle("Напоминание", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker(
                            "Время",
                            selection: Binding(
                                get: { reminderDate },
                                set: { setReminderDate($0) }),
                            displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Напоминания")
                } footer: {
                    Text("Локальное уведомление — работает без платного аккаунта Apple.")
                }

                Section {
                    Button {
                        onboarding = OnboardingPlanBuilder.make(context: context)
                    } label: {
                        Label("Показать знакомство", systemImage: "sparkles")
                    }
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Журнал событий", systemImage: "text.alignleft")
                    }
                } footer: {
                    Text("Что происходило внутри приложения. Если что-то повело себя "
                         + "странно — журнал можно переслать одним нажатием, это "
                         + "быстрее любых описаний.")
                }
            }
            .navigationTitle("Настройки")
            .onAppear { apiKey = Keychain.get(Keychain.claudeAPIKey) ?? "" }
            .sheet(item: $onboarding) { plan in
                OnboardingView(plan: plan)
            }
            .onChange(of: reminderEnabled) { _, enabled in
                Task { await applyReminder(enabled: enabled) }
            }
        }
    }

    private var levelSection: some View {
        Section {
            Picker("Уровень английского", selection: Binding(
                get: { storedLevel.flatMap(CEFRLevel.init(rawValue:)) },
                set: { storedLevel = $0?.rawValue })
            ) {
                Text("Не выбран").tag(CEFRLevel?.none)
                ForEach(CEFRLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(CEFRLevel?.some(level))
                }
            }
            Button("Пройти тест словаря", systemImage: "text.magnifyingglass") {
                showPlacementTest = true
            }
        } footer: {
            Text("По уровню подбираются слова в наборах от Claude — на ступень выше, "
                 + "чтобы не было ни скучно, ни бесполезно редко.")
        }
        .sheet(isPresented: $showPlacementTest) {
            PlacementTestView { storedLevel = $0.rawValue }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Шрифт", selection: Binding(
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
                Text("Turn out · оказаться")
                    .font(.app(.title3, weight: .semibold))
                Text("It turned out he was right all along. Оказалось, он был прав.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Оформление")
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
