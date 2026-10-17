import Foundation
import Observation
import DeclaredAgeRange
import AJFMCore

/// Проверка возраста по закону (P-75) — только там, где закон её требует.
/// Решение — в `AgeAssurance` (Core); здесь — разговор с системой.
/// Хранится только решение и дата, сам возраст не сохраняется и на сервер
/// не уходит.
@MainActor
@Observable
final class AgeAssuranceService {
    static let shared = AgeAssuranceService()
    nonisolated private static let key = "ageCheck"

    /// nil — проверки ещё не было (или закон не требует).
    private(set) var decision: AgeDecision?
    private(set) var checking = false

    private init() {
        decision = Self.storedRecord?.decision
    }

    /// Последняя проверка — читается и вне главного потока (аналитика).
    nonisolated static var storedRecord: AgeCheckRecord? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AgeCheckRecord.self, from: data)
    }

    var allowsAccess: Bool { decision.map(AgeAssurance.allowsAccess) ?? true }

    /// `force` — человек сам нажал «Поделиться возрастом» на заслонке.
    func checkIfNeeded(request: DeclaredAgeRangeAction, force: Bool = false) async {
        guard !UITesting.isActive, !checking else { return }
        let now = Date()
        guard force || AgeAssurance.shouldCheck(last: Self.storedRecord, now: now) else { return }
        checking = true
        defer { checking = false }

        // Не узнали, требует ли закон, — прошлое решение остаётся в силе.
        guard let required = await isRequired() else { return }
        var bracket: AgeBracket?
        if required {
            do {
                let (first, second, third) = AgeAssurance.ageGates
                switch try await request(ageGates: first, second, third) {
                case .sharing(let range):
                    bracket = AgeAssurance.bracket(lowerBound: range.lowerBound,
                                                   upperBound: range.upperBound)
                case .declinedSharing:
                    bracket = nil
                @unknown default:
                    bracket = nil
                }
            } catch {
                // Сбой системы (нет сети, не вошли в iCloud) — не запираем
                // человека, спросим при следующем запуске.
                Log.warning(.app, "Возраст не получен", detail: String(describing: error))
                return
            }
        }
        let next = AgeAssurance.decision(required: required, bracket: bracket)
        save(AgeCheckRecord(decision: next, checkedAt: now))
        decision = next
        if !AgeAssurance.allowsAnalytics(next) {
            UserDefaults.standard.set(false, forKey: SettingsKey.analyticsConsent)
        }
        Log.info(.app, "Проверка возраста", detail: next.rawValue)
    }

    /// Требует ли закон проверку у этого Apple ID; nil — система не ответила.
    /// До iOS 26.2 система такого не умеет — спрашивать не у кого.
    private func isRequired() async -> Bool? {
        do {
            if #available(iOS 26.4, *) {
                return try await AgeRangeService.shared.requiredRegulatoryFeatures
                    .contains(.declaredAgeRangeRequired)
            }
            if #available(iOS 26.2, *) {
                return try await AgeRangeService.shared.isEligibleForAgeFeatures
            }
            return false
        } catch {
            // Без права Declared Age Range (бесплатный аккаунт) система
            // отвечает ошибкой — значит, проверка этой сборке недоступна.
            Log.warning(.app, "Требования к возрасту не получены", detail: String(describing: error))
            return nil
        }
    }

    private func save(_ record: AgeCheckRecord) {
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
