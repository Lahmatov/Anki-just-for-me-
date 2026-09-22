import Foundation

/// Результат проверки произношения на устройстве.
public struct PronunciationAssessment: Equatable, Sendable {
    public enum Verdict: String, Sendable {
        /// Распознано ровно то слово, которое просили.
        case matched
        /// Распознано другое слово — это уже честный сигнал об ошибке.
        case mismatched
        /// Распознаватель не уверен или вернул пустоту.
        case unclear
    }

    public var verdict: Verdict
    public var recognized: String
    public var expected: String
    public var confidence: Double
    /// Другие гипотезы распознавателя, по убыванию уверенности.
    public var alternatives: [String]
    public var message: String
    /// Можно ли доверять этому выводу.
    public var isReliable: Bool

    public var isAccepted: Bool { verdict == .matched }
}

/// Оценка произношения по результату распознавания речи.
///
/// **Главная ловушка всей затеи.** Распознавание речи ≠ проверка произношения.
/// Распознаватель подгоняет услышанное под свой словарь: скажешь «wark» вместо
/// «work» — он вернёт «work», потому что слова «wark» в языке нет. Приложение
/// похвалит, а произношение останется кривым.
///
/// Поэтому здесь нигде не написано «Отлично!». Честная формулировка —
/// «распознано как X с уверенностью Y», и отдельно отмечается, что проверка
/// на устройстве мягкая. Строгую пофонемную оценку даёт только облачный разбор
/// (см. docs/research.md, раздел 3), а на устройстве настоящий сигнал дают
/// минимальные пары — см. `MinimalPairLibrary`.
public enum PronunciationEvaluator {

    /// Ниже этого порога вывод распознавателя ничего не значит.
    public static let confidenceFloor: Double = 0.3
    /// Выше этого — можно опираться на результат.
    public static let confidenceCeiling: Double = 0.6

    public static func evaluate(
        expected: String,
        recognized: String,
        confidence: Double,
        alternatives: [String] = []
    ) -> PronunciationAssessment {
        let target = TermNormalizer.normalize(expected)
        let heard = TermNormalizer.normalize(recognized)
        let reliable = confidence >= confidenceCeiling

        guard !heard.isEmpty else {
            return PronunciationAssessment(
                verdict: .unclear, recognized: "", expected: expected,
                confidence: confidence, alternatives: alternatives,
                message: "Ничего не распознал. Попробуй ближе к микрофону и без спешки.",
                isReliable: false)
        }

        if heard == target {
            return PronunciationAssessment(
                verdict: .matched, recognized: recognized, expected: expected,
                confidence: confidence, alternatives: alternatives,
                message: reliable
                    ? "Распознано как «\(recognized)» — то, что нужно."
                    : "Распознано как «\(recognized)», но распознаватель не уверен. "
                        + "Он подгоняет услышанное под словарь, так что это ещё не гарантия.",
                isReliable: reliable)
        }

        if confidence < confidenceFloor {
            return PronunciationAssessment(
                verdict: .unclear, recognized: recognized, expected: expected,
                confidence: confidence, alternatives: alternatives,
                message: "Разобрал плохо — послышалось «\(recognized)». "
                    + "Скорее всего, дело в записи, а не в тебе. Попробуй ещё раз.",
                isReliable: false)
        }

        return PronunciationAssessment(
            verdict: .mismatched, recognized: recognized, expected: expected,
            confidence: confidence, alternatives: alternatives,
            message: "Услышал «\(recognized)» вместо «\(expected)». "
                + "Это уже настоящий сигнал: распознаватель обычно подгоняет "
                + "результат под знакомые слова, и если он услышал другое — "
                + "звучало действительно иначе.",
            isReliable: true)
    }

    /// Честное предупреждение о пределах проверки на устройстве.
    public static let onDeviceDisclaimer =
        "Проверка на устройстве мягкая: распознаватель подгоняет услышанное под "
        + "знакомые слова и может засчитать неточное произношение. Настоящую "
        + "проверку дают минимальные пары и разбор по звукам."
}
