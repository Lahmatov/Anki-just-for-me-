import Foundation

/// Готовые запросы, которые копируются в буфер и отправляются мне в чат.
///
/// Смысл в том, чтобы не формулировать каждый раз заново и сразу получать
/// файл в нужном формате — его останется только переслать в приложение.
enum PromptTemplates {

    static func newDeck(source: String, words: [String]) -> String {
        let wordList = words.isEmpty
            ? "<вставь сюда слова, которые выписал>"
            : words.joined(separator: ", ")

        return """
        Сделай набор карточек в формате ajfm-deck (JSON) по этим словам \
        из «\(source)»:

        \(wordList)

        Требования:
        - deck.name: «\(source)», deck.folder: «Сериалы/\(source)»
        - translation — кратко, 1–3 варианта; ipa — американская транскрипция
        - example — реальная фраза из этой серии, не словарный пример
        - cloze — тот же пример с ___ на месте слова
        - note — только если есть подвох: ложный друг, отделяемый фразовый
          глагол, разница с британским вариантом
        - не больше 30 слов в наборе

        \(skeleton)
        """
    }

    /// Точный скелет файла. Без него модель называет список как придётся —
    /// `cards`, `words` — и импорт спотыкается. Приложение такие варианты
    /// теперь понимает, но образец надёжнее любой догадки.
    static let skeleton = """
    Верни ровно такой JSON, одним блоком и без пояснений. Список слов \
    называется "notes":

    {
      "format": "ajfm-deck",
      "version": 1,
      "deck": { "name": "…", "folder": "…" },
      "notes": [
        {
          "term": "pull off",
          "translation": "провернуть, суметь",
          "ipa": "/ˌpʊl ˈɔf/",
          "partOfSpeech": "phrasal verb",
          "example": "I can't believe we pulled it off.",
          "exampleTranslation": "Не верится, что у нас получилось.",
          "cloze": "I can't believe we ___ it off.",
          "note": "Отделяемый: pull it off, не pull off it."
        }
      ]
    }

    partOfSpeech — одно из: noun, verb, adjective, adverb, phrasal verb, \
    idiom, phrase, other.
    """

    static let existingWordsHint = """
    Вот слова, которые у меня уже есть — не добавляй их повторно:
    """

    static func deckFromText(source: String) -> String {
        """
        Вот текст (субтитры, статья, диалог) из «\(source)». Выбери из него \
        слова и выражения уровня B1–B2, которые стоит выучить, и сделай набор \
        карточек: примеры бери прямо из этого текста, транскрипция американская, \
        не больше 30 слов.

        <текст>
        …вставь сюда текст…
        </текст>

        \(skeleton)
        """
    }
}
