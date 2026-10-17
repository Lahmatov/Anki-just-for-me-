import Foundation

/// События аналитики (P-74) — заранее, до выбора сервиса.
///
/// Практика из ios-good-practices: все вызовы аналитики — через одну тонкую
/// прослойку, тогда сервис меняется в одном месте. Своё правило сверху —
/// GDPR: в событиях только перечислимые значения и округлённые числа, никаких
/// слов, текстов, имён и номеров. Без согласия человека событие не уходит никуда.
public enum AnalyticsEvent: Equatable, Sendable {
    case sessionFinished(cards: Int, accuracy: Double)
    case lessonCreated(source: LessonSource)
    case drillFinished(mode: String, score: Double)
    case quizFinished(passed: Bool)
    case studyLanguageSwitched(to: StudyLanguage)
    case supportSent(category: SupportCategory)
    case reviewPrompted

    public enum LessonSource: String, Sendable { case text, photo, pdf, chat }

    public var name: String {
        switch self {
        case .sessionFinished: return "session_finished"
        case .lessonCreated: return "lesson_created"
        case .drillFinished: return "drill_finished"
        case .quizFinished: return "quiz_finished"
        case .studyLanguageSwitched: return "study_language_switched"
        case .supportSent: return "support_sent"
        case .reviewPrompted: return "review_prompted"
        }
    }

    public var properties: [String: String] {
        switch self {
        case .sessionFinished(let cards, let accuracy):
            return ["cards": Self.bucket(cards), "accuracy": Self.percentBucket(accuracy)]
        case .lessonCreated(let source):
            return ["source": source.rawValue]
        case .drillFinished(let mode, let score):
            return ["mode": DrillMode(rawValue: mode)?.rawValue ?? "other", "score": Self.percentBucket(score)]
        case .quizFinished(let passed):
            return ["passed": passed ? "yes" : "no"]
        case .studyLanguageSwitched(let language):
            return ["to": language.rawValue]
        case .supportSent(let category):
            return ["category": category.rawValue]
        case .reviewPrompted:
            return [:]
        }
    }

    /// Число карточек — корзинами: точное число ничего не добавляет, но
    /// вместе с временем помогало бы узнать человека.
    static func bucket(_ count: Int) -> String {
        switch count {
        case ..<1: return "0"
        case 1...10: return "1-10"
        case 11...25: return "11-25"
        case 26...50: return "26-50"
        default: return "50+"
        }
    }

    /// Доля — десятками процентов, «0», «10» … «100».
    static func percentBucket(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let clamped = min(max(value, 0), 1)
        return String(Int((clamped * 10).rounded(.down)) * 10)
    }
}

/// Пропускает событие, только если человек согласился (P-74).
public struct AnalyticsGate: Sendable {
    public var consent: Bool

    public init(consent: Bool) {
        self.consent = consent
    }

    public func payload(_ event: AnalyticsEvent) -> (name: String, properties: [String: String])? {
        consent ? (event.name, event.properties) : nil
    }
}
