import Foundation

/// «Спросить Мончика» в Monchik Help: вопросы о приложении, ответы ИИ.
///
/// Каждый вопрос — отдельный запрос без истории: помощнику не нужен
/// контекст беседы, а без истории нечего подделывать и нечем раздуть
/// расход. Всё, что знает помощник, — `facts` ниже: те же ответы, что в
/// частых вопросах, чтобы ИИ не выдумывал функций, которых нет.
public enum HelpChat {

    public struct Message: Codable, Equatable, Sendable, Identifiable {
        public enum Author: String, Codable, Sendable { case user, monchik }

        public var id: UUID
        public var author: Author
        public var text: String
        public var date: Date
        /// Мончик советует написать человеку — показать кнопку письма.
        public var suggestEmail: Bool

        public init(id: UUID = UUID(), author: Author, text: String, date: Date = Date(),
                    suggestEmail: Bool = false) {
            self.id = id
            self.author = author
            self.text = text
            self.date = date
            self.suggestEmail = suggestEmail
        }
    }

    public struct Reply: Equatable, Sendable {
        public var answer: String
        public var onTopic: Bool
        public var suggestEmail: Bool

        public init(answer: String, onTopic: Bool, suggestEmail: Bool) {
            self.answer = answer
            self.onTopic = onTopic
            self.suggestEmail = suggestEmail
        }
    }

    public static let questionLimit = 500
    public static let answerLimit = 700
    /// Сколько сообщений хранить на телефоне: помощник — не архив переписки.
    public static let historyLimit = 40
    public static let maxTokens = 500

    public static let outputSchemaJSON = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["answer", "onTopic", "suggestEmail"],
      "properties": {
        "answer": { "type": "string" },
        "onTopic": { "type": "boolean" },
        "suggestEmail": { "type": "boolean" }
      }
    }
    """

    /// Инструкция помощнику. Факты — из частых вопросов на английском:
    /// модель отвечает на языке человека, а факты одни.
    public static func system(language: AppLanguage) -> String {
        let facts = HelpCenter.entries.map { entry in
            "- \(entry.id): " + englishAnswer(entry.id)
        }.joined(separator: "\n")
        return """
        You are Monchik, the friendly moose in the Recap app, answering questions about how to \
        use the app. Recap teaches American English through TV shows with flashcards and spaced \
        repetition.

        Answer in \(language.promptName), in at most 4 short sentences, warm and simple.
        Use ONLY these facts about the app. If the facts don't cover the question, say you're \
        not sure and set suggestEmail to true — a human will answer by e-mail. Never invent \
        features, prices or settings.

        FACTS:
        \(facts)

        Set onTopic to false if the question is not about the Recap app or learning English \
        with it (homework, code, news, anything else). Reply only with JSON following the schema.
        """
    }

    /// Готовый ответ на вопрос не по теме — модель его не пишет, чтобы
    /// помощника нельзя было превратить в бесплатный чат обо всём.
    public static var offTopicReply: String {
        tr("Я помогаю только с Recap — как учить слова, сериалы, подписка, настройки. "
               + "Спроси меня об этом!",
           "Só ajudo com o Recap — palavras, séries, subscrição, definições. Pergunta-me sobre isso!",
           "I only help with Recap — words, shows, subscription, settings. Ask me about that!")
    }

    public enum ReplyError: Error, Equatable { case unreadable }

    public static func parseReply(_ text: String) throws -> Reply {
        guard let object = (try? DeckNormalizer.jsonObject(from: Data(text.utf8))) as? [String: Any],
              let answer = (object["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !answer.isEmpty else {
            throw ReplyError.unreadable
        }
        let onTopic = object["onTopic"] as? Bool ?? true
        return Reply(answer: onTopic ? String(answer.prefix(answerLimit)) : offTopicReply,
                     onTopic: onTopic,
                     suggestEmail: onTopic && (object["suggestEmail"] as? Bool ?? false))
    }

    /// Вопрос, годный к отправке, или nil.
    public static func cleanQuestion(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        return String(trimmed.prefix(questionLimit))
    }

    /// Хвост истории, не длиннее лимита.
    public static func trimmed(_ history: [Message]) -> [Message] {
        Array(history.suffix(historyLimit))
    }

    /// Ответы частых вопросов по-английски — для инструкции модели.
    private static func englishAnswer(_ id: String) -> String {
        let saved = Loc.language
        Loc.language = .english
        defer { Loc.language = saved }
        return HelpCenter.entries.first { $0.id == id }?.answer ?? ""
    }
}
