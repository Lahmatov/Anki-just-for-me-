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
                message: tr("Ничего не распознал. Попробуй ближе к микрофону и без спешки.",
                            "Não reconheci nada. Tenta mais perto do microfone e sem pressa.",
                            "Nothing recognized. Try closer to the microphone and without rushing."),
                isReliable: false)
        }

        if heard == target {
            return PronunciationAssessment(
                verdict: .matched, recognized: recognized, expected: expected,
                confidence: confidence, alternatives: alternatives,
                message: reliable
                    ? tr("Распознано как «\(recognized)» — то, что нужно.",
                         "Reconhecido como «\(recognized)» — é isso mesmo.",
                         "Recognized as “\(recognized)” — just right.")
                    : tr("Распознано как «\(recognized)», но распознаватель не уверен. "
                            + "Он подгоняет услышанное под словарь, так что это ещё не гарантия.",
                         "Reconhecido como «\(recognized)», mas sem certeza. O reconhecedor "
                            + "ajusta o que ouve ao dicionário, por isso ainda não é garantia.",
                         "Recognized as “\(recognized)”, but not confidently. The recognizer "
                            + "fits what it hears to the dictionary, so this is no guarantee yet."),
                isReliable: reliable)
        }

        if confidence < confidenceFloor {
            return PronunciationAssessment(
                verdict: .unclear, recognized: recognized, expected: expected,
                confidence: confidence, alternatives: alternatives,
                message: tr("Разобрал плохо — послышалось «\(recognized)». "
                                + "Скорее всего, дело в записи, а не в тебе. Попробуй ещё раз.",
                            "Percebi mal — pareceu «\(recognized)». "
                                + "Provavelmente é da gravação, não de ti. Tenta outra vez.",
                            "Hard to make out — sounded like “\(recognized)”. "
                                + "Most likely it's the recording, not you. Try again."),
                isReliable: false)
        }

        return PronunciationAssessment(
            verdict: .mismatched, recognized: recognized, expected: expected,
            confidence: confidence, alternatives: alternatives,
            message: tr("Услышал «\(recognized)» вместо «\(expected)». "
                            + "Это уже настоящий сигнал: распознаватель обычно подгоняет "
                            + "результат под знакомые слова, и если он услышал другое — "
                            + "звучало действительно иначе.",
                        "Ouvi «\(recognized)» em vez de «\(expected)». "
                            + "Isto já é um sinal a sério: o reconhecedor costuma ajustar "
                            + "o resultado a palavras conhecidas, e se ouviu outra coisa, "
                            + "soou mesmo diferente.",
                        "Heard “\(recognized)” instead of “\(expected)”. "
                            + "That's a real signal: the recognizer usually bends results "
                            + "toward familiar words, so if it heard something else, "
                            + "it really sounded different."),
            isReliable: true)
    }

    /// Честное предупреждение о пределах проверки на устройстве.
    public static var onDeviceDisclaimer: String {
        tr("Проверка на устройстве мягкая: распознаватель подгоняет услышанное под "
            + "знакомые слова и может засчитать неточное произношение. Настоящую "
            + "проверку дают минимальные пары и разбор по звукам.",
           "A verificação no dispositivo é branda: o reconhecedor ajusta o que ouve "
            + "a palavras conhecidas e pode aceitar uma pronúncia imprecisa. A "
            + "verificação a sério vem dos pares mínimos e da análise por sons.",
           "On-device checking is lenient: the recognizer fits what it hears to "
            + "familiar words and may accept imprecise pronunciation. The real "
            + "check comes from minimal pairs and sound-by-sound analysis.")
    }
}
