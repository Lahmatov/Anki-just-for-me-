import Foundation

/// Проверка возраста там, где её требует закон (P-75): Техас (SB 2420,
/// действует с июня 2026), дальше — Юта, Луизиана и другие. Apple сама
/// спрашивает возраст у владельца Apple ID и отдаёт приложению только
/// группу: младше 13, 13–15, 16–17, 18+. Дата рождения к нам не попадает.
///
/// Здесь — решение по ответу системы; вызов DeclaredAgeRange живёт
/// в приложении. Там, где закон не требует, возраст не спрашиваем вовсе:
/// лишние данные — лишняя обязанность (GDPR, ст. 5 — минимизация).
public enum AgeBracket: String, Codable, Sendable {
    case under13, from13to15, from16to17, adult
}

public enum AgeDecision: String, Codable, Sendable {
    /// Закон не требует проверки — приложение работает как обычно.
    case notRequired
    case adult
    /// 13–17: приложение работает; покупки Apple сама проводит через
    /// согласие родителя, а мы не предлагаем аналитику.
    case minor
    /// Младше 13: Recap не для детей (COPPA, рейтинг 13+) — дальше не пускаем.
    case underMinimumAge
    /// Закон требует, а возраст не передан — просим поделиться ещё раз.
    case needsAge
}

/// Что запомнили после проверки — только решение и дата, без самого возраста.
public struct AgeCheckRecord: Codable, Equatable, Sendable {
    public var decision: AgeDecision
    public var checkedAt: Date

    public init(decision: AgeDecision, checkedAt: Date) {
        self.decision = decision
        self.checkedAt = checkedAt
    }
}

public enum AgeAssurance {
    /// Минимальный возраст Recap — тот же, что рейтинг в App Store.
    public static let minimumAge = 13
    /// Границы для запроса: совпадают с группами закона Техаса.
    public static let ageGates = (13, 16, 18)
    /// Взрослого переспрашиваем раз в месяц, подростка — каждый запуск:
    /// подросток взрослеет, а родитель может отозвать согласие.
    public static let adultRecheckDays = 30

    /// Группа по границам ответа системы. Нижней границы нет — младше
    /// самой низкой. Решает нижняя граница: система может заменить наши
    /// границы своими, и «16 и старше» без верхней — ещё не взрослый.
    public static func bracket(lowerBound: Int?, upperBound: Int?) -> AgeBracket {
        guard let lower = lowerBound else { return .under13 }
        if lower >= 18 { return .adult }
        if lower >= 16 { return .from16to17 }
        if lower >= minimumAge { return .from13to15 }
        return .under13
    }

    /// Решение: `required` — требует ли закон проверку у этого человека;
    /// `bracket` — nil, если возраст не передан.
    public static func decision(required: Bool, bracket: AgeBracket?) -> AgeDecision {
        guard required else { return .notRequired }
        switch bracket {
        case nil: return .needsAge
        case .under13: return .underMinimumAge
        case .from13to15, .from16to17: return .minor
        case .adult: return .adult
        }
    }

    /// Пора ли спрашивать систему снова. Сбой системы — не повод запирать
    /// человека: прошлое «можно» действует, пока не пришёл новый ответ.
    public static func shouldCheck(last: AgeCheckRecord?, now: Date) -> Bool {
        guard let last else { return true }
        switch last.decision {
        case .adult:
            return now.timeIntervalSince(last.checkedAt) >= Double(adultRecheckDays) * 86_400
        case .notRequired, .minor, .underMinimumAge, .needsAge:
            return true
        }
    }

    /// Пускать ли в приложение.
    public static func allowsAccess(_ decision: AgeDecision) -> Bool {
        switch decision {
        case .notRequired, .adult, .minor: return true
        case .underMinimumAge, .needsAge: return false
        }
    }

    /// Предлагать ли аналитику: у несовершеннолетних — нет, даже с согласием.
    public static func allowsAnalytics(_ decision: AgeDecision?) -> Bool {
        decision != .minor && decision != .underMinimumAge
    }
}

/// «Существенное изменение» приложения (SB 2420): после такого выпуска
/// подросток в Техасе не получает его без нового согласия родителя.
/// Что считать существенным, решает разработчик; для Recap — новый вид
/// данных, которые уходят с телефона, новый собеседник-ИИ, покупки
/// нового рода. Список пуст: первый выпуск изменением не считается.
public struct SignificantChange: Equatable, Sendable {
    public let id: String
    /// Версия, в которой изменение появилось.
    public let introducedIn: String
    public let summary: String

    public init(id: String, introducedIn: String, summary: String) {
        self.id = id
        self.introducedIn = introducedIn
        self.summary = summary
    }
}

public enum SignificantChanges {
    /// Перед первой записью сюда — экран согласия родителя (PermissionKit,
    /// `SignificantAppUpdateTopic`); тест держит список пустым до тех пор.
    public static let all: [SignificantChange] = []

    /// Что человек ещё не видел: изменения новее версии, с которой он начал
    /// (кто поставил уже с изменением, соглашался при загрузке), и не
    /// отмеченные как принятые.
    public static func pending(_ changes: [SignificantChange], originalVersion: String,
                               handled: Set<String>) -> [SignificantChange] {
        changes.filter {
            !handled.contains($0.id) && compare($0.introducedIn, originalVersion) == .orderedDescending
        }
    }

    /// Сравнение версий по числам: «1.10» новее «1.9», «1.0» равна «1».
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
