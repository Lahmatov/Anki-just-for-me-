import Foundation
import MetricKit
import AJFMCore

/// Сбои и зависания от iOS через MetricKit (P-74): отчёты приходят на сам
/// телефон раз в сутки или при следующем запуске после падения. Храним
/// месячную сводку локально; в поддержку она уходит только вместе с
/// обращением и только с включённой диагностикой.
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsService()
    static let key = "crashLog"

    func start() {
        MXMetricManager.shared.add(self)
    }

    static var records: [CrashRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CrashRecord].self, from: data)) ?? []
    }

    /// Сводка для обращения в поддержку: число сбоев и зависаний за месяц.
    static var summary: [String: String] { CrashLog.summary(records) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var fresh: [CrashRecord] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                fresh.append(CrashRecord(
                    kind: .crash, date: payload.timeStampEnd,
                    reason: CrashLog.reason(signal: crash.signal?.intValue,
                                            exceptionType: crash.exceptionType?.intValue),
                    appVersion: crash.metaData.applicationBuildVersion))
            }
            for hang in payload.hangDiagnostics ?? [] {
                fresh.append(CrashRecord(kind: .hang, date: payload.timeStampEnd, reason: "hang",
                                         appVersion: hang.metaData.applicationBuildVersion))
            }
        }
        guard !fresh.isEmpty else { return }
        let merged = CrashLog.merge(Self.records, adding: fresh, now: Date())
        if let data = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        Log.warning(.app, "iOS сообщила о сбоях", detail: "\(fresh.count)")
    }
}

/// Аналитика (P-74) — одна точка входа. Сервиса пока нет: событие с
/// согласием остаётся в журнале на телефоне. Подключение PostHog — замена
/// одной строки здесь (docs/gdpr.md, «Обработчики»).
enum AnalyticsService {
    /// Согласие человека — и не несовершеннолетний (P-75): у подростков
    /// аналитики нет, даже если согласие когда-то дали.
    static var consent: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.analyticsConsent)
            && AgeAssurance.allowsAnalytics(AgeAssuranceService.storedRecord?.decision)
    }

    static func track(_ event: AnalyticsEvent) {
        guard let payload = AnalyticsGate(consent: consent).payload(event) else { return }
        let details = payload.properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        Log.info(.app, "Событие " + payload.name, detail: details.joined(separator: " "))
    }
}

/// Просьба оценить приложение (P-74) — после праздника, по правилам `ReviewPrompt`.
@MainActor
enum ReviewPromptService {
    private static let key = "reviewPromptState"

    private static var state: ReviewPromptState {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let saved = try? JSONDecoder().decode(ReviewPromptState.self, from: data) {
                return saved
            }
            let first = ReviewPromptState(firstLaunch: Date())
            save(first)
            return first
        }
        set { save(newValue) }
    }

    private static func save(_ state: ReviewPromptState) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Запомнить первый запуск — от него отсчитывается неделя.
    static func noteLaunch() { _ = state }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Пора ли просить: в UI-тестах — никогда, окно App Store им мешает.
    static func shouldAsk(studyDays: Int, moment: ReviewPrompt.Moment?) -> Bool {
        guard !UITesting.isActive else { return false }
        return ReviewPrompt.shouldAsk(now: Date(), state: state, appVersion: appVersion,
                                      studyDays: studyDays, moment: moment)
    }

    static func markAsked() {
        state = ReviewPrompt.asked(state, now: Date(), appVersion: appVersion)
        AnalyticsService.track(.reviewPrompted)
    }
}
