import SwiftUI
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
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 20
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0

    private var speech: SpeechService { SpeechService.shared }

    var body: some View {
        NavigationStack {
            Form {
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
                            .font(.caption)
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
            }
            .navigationTitle("Настройки")
            .onChange(of: reminderEnabled) { _, enabled in
                Task { await applyReminder(enabled: enabled) }
            }
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
