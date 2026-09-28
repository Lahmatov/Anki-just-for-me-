import Foundation

/// Разговор с Мончиком о просмотренной серии.
///
/// Пересказ проверяет, понял ли человек сюжет. Разговор тренирует другое —
/// отвечать на вопросы вживую: почему герой так поступил, что будет дальше,
/// на чьей ты стороне. Мончик спрашивает по одному вопросу, после ответа
/// даёт не больше одной поправки — длинный разбор посреди беседы её убивает —
/// и задаёт следующий.
///
/// Факты о серии — только из эталона (описания или субтитров), по тому же
/// правилу, что и в разборе пересказа: память модели о сериале ненадёжна.
public enum EpisodeDiscussion {

    public enum Speaker: String, Codable, Sendable {
        case monchik, learner
    }

    /// Поправка к ответу: что сказано, как лучше и почему.
    public struct Tip: Codable, Equatable, Sendable {
        public var said: String
        public var better: String
        public var why: String

        public init(said: String, better: String, why: String) {
            self.said = said
            self.better = better
            self.why = why
        }
    }

    public struct Turn: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var speaker: Speaker
        public var text: String
        /// Поправка к предыдущему ответу ученика — только у реплик Мончика.
        public var tip: Tip?

        public init(id: UUID = UUID(), speaker: Speaker, text: String, tip: Tip? = nil) {
            self.id = id
            self.speaker = speaker
            self.text = text
            self.tip = tip
        }
    }

    /// Ответ модели.
    public struct Reply: Equatable, Sendable {
        public var text: String
        public var tip: Tip?
        public var finished: Bool
    }

    /// Сколько ответов ученика до прощания. Шесть вопросов — минут пять
    /// разговора: достаточно, чтобы разговориться, и не успевает надоесть.
    public static let maxLearnerTurns = 6
    /// Эталон длиннее обрезается: он уходит с каждым ходом и оплачивается
    /// каждый раз, а для разговора хватает начала.
    public static let referenceLimit = 8_000
    public static let maxTokens = 1_500
    public static let estimatedOutputTokens = 300

    public static let outputSchemaJSON = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["reply", "tip", "finished"],
      "properties": {
        "reply": { "type": "string" },
        "tip": {
          "type": "object",
          "additionalProperties": false,
          "required": ["said", "better", "why"],
          "properties": {
            "said": { "type": "string" },
            "better": { "type": "string" },
            "why": { "type": "string" }
          }
        },
        "finished": { "type": "boolean" }
      }
    }
    """

    // MARK: - Запрос

    public static func system(
        language: AppLanguage, level: CEFRLevel?, episodeTitle: String,
        reference: RetellReference?, retelling: String?
    ) -> String {
        let levelLine = level.map {
            "The learner's level is about \($0.rawValue): use words and grammar they can "
                + "follow, a little above that level at most."
        } ?? "The learner is intermediate (about B1–B2): keep the language simple and natural."

        var parts = ["""
        You are Monchik, a friendly cartoon moose from Monchegorsk who loves TV shows. \
        You chat in American English with an adult learner whose native language is \
        \(language.promptName). You both just watched the episode "\(episodeTitle)".

        \(levelLine)

        How to talk:
        - Ask ONE open question at a time about the episode: what happened, why a \
        character did something, how the learner feels about it, what might happen next.
        - Start with easy questions about the plot, then move to opinions.
        - React to what the learner said in one or two sentences before the next question.
        - Keep every reply under 60 words. Warm, curious, a little playful; never lecture.
        - The learner speaks through speech recognition: ignore obvious recognition \
        errors, do not correct them.

        Corrections go ONLY into "tip", never into "reply":
        - At most one tip per turn, for the most useful mistake in the learner's last \
        message: "said" — their words, "better" — the natural American way, "why" — \
        one short sentence in \(language.promptName).
        - No real mistake — leave all three fields of the tip empty. Do not invent one.
        - On your very first turn the tip is empty.

        Facts about the episode:
        - Use ONLY the reference below. Do not rely on your memory of the show.
        - If the learner says something the reference does not cover, do not call it \
        wrong: say you don't remember that part and ask about it.
        - Never reveal events of later episodes.
        """]

        if let reference {
            let text = String(reference.text.prefix(referenceLimit))
            switch reference {
            case .subtitles:
                parts.append("REFERENCE — episode subtitles:\n<subtitles>\n\(text)\n</subtitles>")
            case .synopsis:
                parts.append("REFERENCE — official episode synopsis:\n<synopsis>\n\(text)\n</synopsis>")
            }
        } else {
            parts.append("""
            There is no reference for this episode. Ask about the learner's impressions \
            and opinions rather than plot details, and never state plot facts yourself.
            """)
        }

        if let retelling, !retelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("""
            Earlier the learner retold the episode like this — build on it, ask about \
            what they found interesting or skipped:
            <retelling>
            \(retelling)
            </retelling>
            """)
        }

        parts.append("""
        Set "finished" to true only when you say goodbye. Reply only with JSON following \
        the schema.
        """)
        return parts.joined(separator: "\n\n")
    }

    /// Реплика, с которой разговор начинается: API требует, чтобы первым
    /// говорил пользователь, а начинать должен Мончик.
    static let kickoff = "(The learner opened the chat. Greet them in one short line "
        + "and ask your first question.)"

    static let lastTurnNote = "\n\n(This was the learner's last answer. React to it, give "
        + "the tip if there is one, thank them for the chat and say goodbye. Set finished to true.)"

    public static func learnerTurnCount(_ turns: [Turn]) -> Int {
        turns.filter { $0.speaker == .learner }.count
    }

    /// Пора ли прощаться: ответов ученика набралось на весь разговор.
    public static func isLastTurn(_ turns: [Turn]) -> Bool {
        learnerTurnCount(turns) >= maxLearnerTurns
    }

    /// История для Messages API. Первым всегда идёт служебное сообщение
    /// от ученика, реплики строго чередуются: подряд идущие ответы одной
    /// стороны склеиваются, пустые пропускаются.
    public static func messages(for turns: [Turn]) -> [ClaudeRequest.Turn] {
        var result = [ClaudeRequest.Turn(.user, kickoff)]
        for turn in turns {
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let role: ClaudeRequest.Turn.Role = turn.speaker == .learner ? .user : .assistant
            if result.last?.role == role {
                result[result.count - 1].text += "\n" + text
            } else {
                result.append(ClaudeRequest.Turn(role, text))
            }
        }
        if isLastTurn(turns), result.last?.role == .user {
            result[result.count - 1].text += lastTurnNote
        }
        return result
    }

    // MARK: - Ответ

    public enum ReplyError: Error, Equatable {
        case unreadable
    }

    /// Ответ модели; пустая поправка — это «поправки нет».
    public static func parseReply(_ text: String) throws -> Reply {
        guard let object = (try? DeckNormalizer.jsonObject(from: Data(text.utf8))) as? [String: Any],
              let reply = (object["reply"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else {
            throw ReplyError.unreadable
        }
        var tip: Tip?
        if let raw = object["tip"] as? [String: Any] {
            let said = (raw["said"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let better = (raw["better"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let why = (raw["why"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Поправка без «как лучше» или совпадающая со сказанным — не поправка.
            if !said.isEmpty, !better.isEmpty,
               said.lowercased() != better.lowercased() {
                tip = Tip(said: said, better: better, why: why)
            }
        }
        return Reply(text: reply, tip: tip, finished: object["finished"] as? Bool ?? false)
    }

    // MARK: - Поправки в карточки

    /// Набор из поправок разговора: как лучше сказать — на лицевой стороне,
    /// почему — на обороте, сказанное — в подсказке. Повторы не дублируются.
    /// Поправок нет — набора нет.
    public static func deckFile(from turns: [Turn], name: String, folder: String?) -> DeckFile? {
        var seen = Set<String>()
        let notes = turns.compactMap(\.tip).compactMap { tip -> NoteData? in
            let key = tip.better.lowercased()
            guard seen.insert(key).inserted else { return nil }
            var note = NoteData(term: tip.better, translation: tip.why.isEmpty ? tip.better : tip.why)
            note.note = "✗ " + tip.said
            return note
        }
        guard !notes.isEmpty else { return nil }
        return DeckFile(deck: DeckMeta(name: name, folder: folder, cardTypes: [.recall, .recognition]),
                        notes: notes)
    }
}
