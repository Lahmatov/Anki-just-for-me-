import Foundation

/// С чем сверяется пересказ.
///
/// Субтитры — эталон точный: в них каждая реплика. Описание серии из TVMaze —
/// в три-пять предложений, но есть у каждой серии и не требует искать файл.
/// По описанию можно проверить главное — понял ли человек сюжет, — но не
/// детали: их там просто нет, и засчитывать их ошибками нельзя.
public enum RetellReference: Equatable, Sendable {
    case subtitles(String)
    case synopsis(String)

    public var text: String {
        switch self {
        case .subtitles(let text), .synopsis(let text): return text
        }
    }
}

/// Сборка запроса на разбор пересказа.
///
/// Вся ценность фичи держится на одном правиле: **судить только по субтитрам**.
/// Без эталона модель опирается на то, что «помнит» о сериале, и начинает
/// уверенно сообщать об ошибках, которых не было. Поэтому промпт требует
/// цитату под каждое утверждение, а приложение не даёт запустить разбор
/// без файла субтитров.
public enum RetellPrompt {

    /// Инструкция на языке интерфейса ученика.
    public static var system: String { system(for: Loc.language) }

    /// Сама инструкция — по-английски: так она одинаково понятна модели
    /// при любом языке ученика. Объяснения в разборе — на родном языке
    /// ученика, цитаты и его собственные слова — как есть, по-английски.
    public static func system(for language: AppLanguage) -> String {
        system(for: language, reference: .subtitles(""))
    }

    public static func system(for language: AppLanguage, reference: RetellReference) -> String {
        let rule: String
        switch reference {
        case .subtitles:
            rule = """
            THE IRON RULE: judge the content of the episode ONLY by the attached \
            subtitles. Do not rely on your own knowledge of the show — you may remember \
            it inaccurately or not at all. If a claim cannot be checked against the \
            subtitles, say so instead of calling it a mistake. Back every claim about \
            the content with a short quote from the subtitles.
            """
        case .synopsis:
            rule = """
            THE IRON RULE: judge the content of the episode ONLY by the attached \
            official synopsis. Do not rely on your own knowledge of the show — you may \
            remember it inaccurately or not at all. The synopsis is short: it names the \
            main plot, not every scene. A detail the synopsis does not mention is \
            neither correct nor incorrect — leave it out, never call it a mistake. \
            List as missed only main plot points of the synopsis that the retelling \
            lacks, and base coverage on those main points. Back every claim about the \
            content with a short quote from the synopsis.
            """
        }
        return """
        You teach American English to an adult learner whose native language is \
        \(language.promptName). The learner watched an episode and retold it out \
        loud; the retelling was transcribed automatically and is attached as text.

        \(rule)

        The retelling comes from speech recognition of accented speech. If a word \
        looks like a recognition error rather than a mistake of understanding or \
        grammar, mark it mayBeMisheard and do not count it against the learner.

        Keep two things apart and never mix them:
        1. Understanding of the content — what was understood correctly, what was \
        distorted, what was missed.
        2. Quality of the English — grammar, vocabulary, fluency.

        No more than three items in topPriorities, the most important ones. The \
        learner reads the review after every episode; a wall of text guarantees \
        they stop reading.

        Tone: calm and specific. No praise without a reason and no scolding. \
        Instead of "work on your grammar" — what exactly, where exactly, and how \
        it should be.

        Write every explanation (claim, comment, why, fluencyNote, topPriorities, \
        translation) in \(language.promptName). Quotes from the reference and the \
        learner's own words stay in English exactly as they are.

        Reply ONLY with valid JSON following the schema below, with no markdown \
        wrapper and no text before or after it.
        """
    }

    public static let responseSchema = """
    {
      "understanding": {
        "correct":   [{"claim": "...", "quote": "a quote from the reference"}],
        "incorrect": [{"claim": "...", "quote": "...", "comment": "what actually happened",
                       "mayBeMisheard": false}],
        "missed":    [{"claim": "what was missed", "quote": "..."}],
        "coverage": 0.7
      },
      "language": {
        "grammar":    [{"said": "he don't know", "better": "he doesn't know",
                        "why": "third person singular"}],
        "vocabulary": [{"said": "bad guy", "better": "antagonist",
                        "why": "more precise and natural"}],
        "fluencyNote": "pace, pauses, filler words — one sentence, or null",
        "suggestedWords": [{"term": "antagonist",
                            "translation": "translation into the learner's language",
                            "example": "a line from the reference with this word",
                            "insteadOf": "bad guy"}]
      },
      "topPriorities": ["no more than three items"]
    }
    """

    /// Собирает сообщение пользователя: субтитры как эталон плюс пересказ.
    public static func userMessage(
        subtitles: String,
        retell: String,
        episodeTitle: String?,
        watchedUpTo: TimeInterval?
    ) -> String {
        userMessage(reference: .subtitles(subtitles), retell: retell,
                    episodeTitle: episodeTitle, watchedUpTo: watchedUpTo)
    }

    /// Сообщение с любым эталоном: субтитрами или описанием серии.
    public static func userMessage(
        reference: RetellReference,
        retell: String,
        episodeTitle: String?,
        watchedUpTo: TimeInterval?
    ) -> String {
        var parts: [String] = []

        if let episodeTitle, !episodeTitle.isEmpty {
            parts.append("Episode: \(episodeTitle)")
        }
        if let watchedUpTo, case .subtitles = reference {
            let minutes = Int(watchedUpTo / 60)
            parts.append(
                "The learner watched up to minute \(minutes); "
                + "the subtitles are cut at that point.")
        }

        switch reference {
        case .subtitles(let subtitles):
            parts.append("""
            EPISODE SUBTITLES (the only source of truth about the content):
            <subtitles>
            \(subtitles)
            </subtitles>
            """)
        case .synopsis(let synopsis):
            parts.append("""
            OFFICIAL EPISODE SYNOPSIS (the only source of truth about the content):
            <synopsis>
            \(synopsis)
            </synopsis>
            """)
        }

        parts.append("""
        THE LEARNER'S RETELLING (speech transcript):
        <retelling>
        \(retell)
        </retelling>
        """)

        parts.append("Return the review strictly following the schema:\n\(responseSchema)")

        return parts.joined(separator: "\n\n")
    }

    /// Оценка ответа для лимита расходов: рассуждение модели и длинный
    /// JSON-разбор. Занизить её — значит пропустить запрос, который выйдет
    /// за месячный лимит; потолок запроса — 16 тысяч токенов.
    public static let estimatedOutputTokens = 6_000

    /// Грубая оценка числа токенов — чтобы показать стоимость до отправки.
    /// Для смеси английского и русского ~3.5 символа на токен.
    public static func estimateTokens(_ text: String) -> Int {
        max(1, Int(Double(text.count) / 3.5))
    }
}
