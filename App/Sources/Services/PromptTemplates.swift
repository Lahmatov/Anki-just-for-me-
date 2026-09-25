import Foundation
import AJFMCore

/// Готовый запрос, который копируется в буфер и отправляется в чат с Claude.
///
/// Запасной путь к набору через приложение (DeckRequestView): им пользуются,
/// когда хочется обсудить слова в чате. Инструкция — по-английски, чтобы
/// одинаково работать при любом языке интерфейса; переводы — на языке
/// интерфейса.
enum PromptTemplates {

    static func newDeck(
        source: String, words: [String], language: AppLanguage = Loc.language
    ) -> String {
        let wordList = words.isEmpty
            ? "<paste the words you wrote down here>"
            : words.joined(separator: ", ")
        let translation = language.translatesIntoItself
            ? "translation: a short, plain-English definition"
            : "translation: 1–3 short equivalents in \(language.promptName)"

        return """
        Make a flashcard deck in the ajfm-deck format (JSON) from these words \
        from “\(source)”:

        \(wordList)

        Requirements:
        - deck.name: “\(source)”, deck.folder: “Shows/\(source)”
        - \(translation); ipa: General American transcription
        - example: a real line from this episode, not a dictionary example
        - cloze: the same example with ___ in place of the word
        - note (in \(language.promptName)): only if there is a pitfall — a false \
        friend, a separable phrasal verb, a British/American difference
        - no more than 30 words in the deck

        \(skeleton)
        """
    }

    /// Точный скелет файла. Без него модель называет список как придётся —
    /// `cards`, `words` — и импорт спотыкается. Приложение такие варианты
    /// понимает, но образец надёжнее любой догадки.
    static let skeleton = """
    Reply with exactly this JSON, in one block and with no explanations. \
    The list of words is called "notes":

    {
      "format": "ajfm-deck",
      "version": 1,
      "deck": { "name": "…", "folder": "…" },
      "notes": [
        {
          "term": "pull off",
          "translation": "…",
          "ipa": "/ˌpʊl ˈɔf/",
          "partOfSpeech": "phrasal verb",
          "example": "I can't believe we pulled it off.",
          "exampleTranslation": "…",
          "cloze": "I can't believe we ___ it off.",
          "note": "…"
        }
      ]
    }

    partOfSpeech is one of: noun, verb, adjective, adverb, phrasal verb, \
    idiom, phrase, other.
    """
}
