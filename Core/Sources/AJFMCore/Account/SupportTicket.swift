import Foundation

/// О чём обращение — помогает отвечать быстрее и видеть, что болит чаще (P-72).
public enum SupportCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case bug, question, subscription, privacy, idea

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bug: return tr("Что-то сломалось", "Algo avariou", "Something's broken")
        case .question: return tr("Вопрос", "Pergunta", "Question")
        case .subscription: return tr("Подписка и оплата", "Subscrição e pagamento", "Subscription & billing")
        case .privacy: return tr("Мои данные", "Os meus dados", "My data")
        case .idea: return tr("Идея", "Ideia", "Idea")
        }
    }

    public var symbol: String {
        switch self {
        case .bug: return "ladybug.fill"
        case .question: return "questionmark.bubble.fill"
        case .subscription: return "creditcard.fill"
        case .privacy: return "hand.raised.fill"
        case .idea: return "lightbulb.fill"
        }
    }
}

extension BackendAPI {
    /// Обращение в поддержку. Почта — по желанию: без неё ответ только в приложении.
    public struct SupportTicketBody: Encodable, Equatable, Sendable {
        public static let messageLimit = 4_000

        public var category: String
        public var message: String
        public var contact: String?
        public var diagnostics: [String: String]?

        public init(category: SupportCategory, message: String, contact: String?,
                    diagnostics: [String: String]?) {
            self.category = category.rawValue
            self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(utf16: Self.messageLimit)
            let email = (contact ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.contact = email.isEmpty ? nil : email
            self.diagnostics = diagnostics?.isEmpty == true ? nil : diagnostics
        }

        public var isValid: Bool {
            !message.isEmpty && (contact.map(SupportMail.looksLikeEmail) ?? true)
        }
    }

    public struct SupportTicket: Decodable, Equatable, Sendable, Identifiable {
        public var id: String
        public var category: String
        public var message: String
        public var status: String
        public var reply: String?
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: String, category: String, message: String, status: String, reply: String?,
                    createdAt: Date, updatedAt: Date) {
            self.id = id
            self.category = category
            self.message = message
            self.status = status
            self.reply = reply
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey {
            case id, category, message, status, reply, createdAt, updatedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            category = try container.decodeIfPresent(String.self, forKey: .category) ?? "question"
            message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? "open"
            reply = try container.decodeIfPresent(String.self, forKey: .reply)
            // Сервер отдаёт секунды Unix — как у бэкапов.
            createdAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .createdAt))
            updatedAt = Date(timeIntervalSince1970:
                try container.decodeIfPresent(Double.self, forKey: .updatedAt)
                    ?? createdAt.timeIntervalSince1970)
        }

        public var kind: SupportCategory { SupportCategory(rawValue: category) ?? .question }
        public var isAnswered: Bool { !(reply ?? "").isEmpty }
    }

    public struct SupportTicketResponse: Decodable, Sendable {
        public var ticket: SupportTicket
    }

    public struct SupportTicketList: Decodable, Sendable {
        public var tickets: [SupportTicket]
    }
}

/// Диагностика к обращению: то, о чём иначе пришлось бы переспрашивать.
/// Ни слов, ни прогресса — только версии и языки.
public enum SupportDiagnostics {
    public static func make(appVersion: String, systemVersion: String, device: String,
                            language: AppLanguage, studyLanguage: StudyLanguage,
                            cards: Int? = nil) -> [String: String] {
        var result = ["app": appVersion, "ios": systemVersion, "device": device,
                      "language": language.rawValue, "studyLanguage": studyLanguage.rawValue]
        if let cards { result["cards"] = String(cards) }
        return result
    }
}
