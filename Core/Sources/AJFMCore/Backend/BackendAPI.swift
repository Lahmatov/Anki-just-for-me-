import Foundation

/// Протокол обмена с сервером Recap (backend/): тела запросов, ответы
/// и понятные человеку ошибки.
///
/// Ключа Anthropic в приложении нет: с подпиской или промокодом запросы
/// идут через сервер, и он сам решает, что можно спросить у модели, —
/// только слова к серии и разговор о серии.
public enum BackendAPI {

    // MARK: - Доступ

    public struct PlanStatus: Codable, Equatable, Sendable {
        public var plan: String
        public var active: Bool
        public var unitsTotal: Int
        public var unitsLeft: Int
        public var periodEnd: String?

        public init(plan: String, active: Bool, unitsTotal: Int, unitsLeft: Int, periodEnd: String?) {
            self.plan = plan
            self.active = active
            self.unitsTotal = unitsTotal
            self.unitsLeft = unitsLeft
            self.periodEnd = periodEnd
        }

        public enum Kind: Equatable, Sendable { case none, promo, subscription }

        public var kind: Kind {
            switch plan {
            case "subscription": return .subscription
            case "promo": return .promo
            default: return .none
            }
        }

        /// Сервер пишет даты с миллисекундами («2026-10-28T12:00:00.000Z»).
        public var periodEndDate: Date? {
            guard let periodEnd else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: periodEnd) ?? ISO8601DateFormatter().date(from: periodEnd)
        }

        /// Доля оставшегося лимита, 0…1.
        public var fractionLeft: Double {
            guard unitsTotal > 0 else { return 0 }
            return min(1, max(0, Double(unitsLeft) / Double(unitsTotal)))
        }

        /// Примерно сколько наборов слов ещё можно сделать: единицы людям
        /// ничего не говорят, а «≈ 40 наборов» — понятно.
        public var approximateDecksLeft: Int { unitsLeft / BackendAPI.unitsPerDeck }
    }

    /// Средний набор из 20 слов: ~1500 токенов входа и ~3500 выхода.
    public static let unitsPerDeck = 1_500 + 5 * 3_500

    // MARK: - Набор

    public struct DeckBody: Encodable, Equatable, Sendable {
        public var showId: Int
        public var season: Int
        public var episode: Int
        public var language: String
        public var level: String?
        public var wordCount: Int
        public var knownTerms: [String]
        public var subtitles: String?

        public init(showId: Int, season: Int, episode: Int, language: AppLanguage,
                    level: CEFRLevel?, wordCount: Int, knownTerms: [String], subtitles: String?) {
            self.showId = showId
            self.season = season
            self.episode = episode
            self.language = language.rawValue
            self.level = level?.rawValue
            self.wordCount = min(max(wordCount, DeckRequest.wordCountRange.lowerBound),
                                 DeckRequest.wordCountRange.upperBound)
            // Сервер принимает не больше 400 слов по 80 символов.
            self.knownTerms = Array(knownTerms.filter { $0.count <= 80 }
                .prefix(DeckRequest.knownTermsLimit))
            let trimmed = subtitles?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.subtitles = trimmed.isEmpty ? nil : String(trimmed.prefix(DeckRequest.subtitlesLimit))
        }
    }

    public struct DeckResponse: Decodable, Sendable {
        public var deck: DeckFile
        /// «catalog» — готовый набор без расхода, «model» — собран моделью.
        public var source: String
        public var plan: PlanStatus
    }

    // MARK: - Разговор

    public struct DiscussBody: Encodable, Equatable, Sendable {
        public struct Turn: Encodable, Equatable, Sendable {
            public var speaker: String
            public var text: String
            /// Подпись сервера у реплик Мончика; без неё сервер историю не примет.
            public var sig: String?
        }

        public var showId: Int
        public var season: Int
        public var episode: Int
        public var language: String
        public var level: String?
        public var turns: [Turn]
        public var retelling: String?

        public init(showId: Int, season: Int, episode: Int, language: AppLanguage,
                    level: CEFRLevel?, turns: [EpisodeDiscussion.Turn], retelling: String?) {
            self.showId = showId
            self.season = season
            self.episode = episode
            self.language = language.rawValue
            self.level = level?.rawValue
            self.turns = turns.compactMap { turn in
                // Реплику Мончика нельзя менять ни на символ: подпись сервера
                // сделана по точному тексту.
                if turn.speaker == .monchik {
                    return Turn(speaker: turn.speaker.rawValue, text: turn.text, sig: turn.signature)
                }
                let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return Turn(speaker: turn.speaker.rawValue, text: String(text.prefix(600)), sig: nil)
            }
            let trimmed = retelling?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.retelling = trimmed.isEmpty ? nil : String(trimmed.prefix(4_000))
        }
    }

    public struct DiscussResponse: Decodable, Sendable {
        public var reply: String
        public var tip: EpisodeDiscussion.Tip?
        public var finished: Bool
        public var plan: PlanStatus
        /// Подпись этой реплики — её надо вернуть серверу со следующим ходом.
        public var turnSig: String?
        /// false — просьба была не по теме, и сервер ответил готовой фразой.
        public var onTopic: Bool?

        public var asReply: EpisodeDiscussion.Reply {
            EpisodeDiscussion.Reply(text: reply, tip: tip, finished: finished, signature: turnSig)
        }
    }

    // MARK: - Каталог

    public struct CatalogShow: Decodable, Equatable, Sendable, Identifiable {
        public var showId: Int
        public var name: String
        public var posterUrl: String?
        public var year: Int?
        public var decks: Int

        public var id: Int { showId }
    }

    public struct CatalogResponse: Decodable, Sendable {
        public var shows: [CatalogShow]
    }

    // MARK: - Ошибки

    public struct ErrorBody: Decodable, Sendable {
        public var error: String
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case server(code: String, status: Int)
        case notConfigured
        case network

        /// Ошибка из ответа сервера: код из тела, а если тела нет — по статусу.
        public static func from(status: Int, body: Data) -> Failure {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
            return .server(code: code ?? "http_\(status)", status: status)
        }

        public var code: String? {
            if case .server(let code, _) = self { return code }
            return nil
        }

        /// Нужна ли подписка или промокод, чтобы продолжить.
        public var needsPlan: Bool {
            ["no_plan", "plan_expired", "quota_exceeded"].contains(code ?? "")
        }

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return tr("Сервер Recap ещё не подключён.", "O servidor Recap ainda não está ligado.",
                          "The Recap server isn't set up yet.")
            case .network:
                return tr("Нет связи с сервером. Проверь интернет.",
                          "Sem ligação ao servidor. Verifica a internet.",
                          "Can't reach the server. Check your connection.")
            case .server(let code, _):
                return Self.message(for: code)
            }
        }

        static func message(for code: String) -> String {
            switch code {
            case "no_plan":
                return tr("Это доступно с Recap Plus или по промокоду.",
                          "Disponível com o Recap Plus ou com um código promocional.",
                          "This needs Recap Plus or a promo code.")
            case "plan_expired":
                return tr("Доступ закончился. Продли подписку или введи промокод.",
                          "O acesso terminou. Renova a subscrição ou usa um código.",
                          "Your access has ended. Renew or use a promo code.")
            case "quota_exceeded":
                return tr("Лимит этого месяца исчерпан. Он обновится с новым периодом подписки.",
                          "O limite deste mês esgotou-se. Renova-se no próximo período.",
                          "This month's limit is used up. It resets with the next period.")
            case "episode_locked":
                return tr("Сначала возьми слова к этой серии — тогда Мончик сможет её обсудить.",
                          "Primeiro obtém as palavras deste episódio — depois o Monchik pode falar sobre ele.",
                          "Get the words for this episode first — then Monchik can talk about it.")
            case "episode_not_found":
                return tr("Такой серии нет в TVMaze. Проверь сезон и номер.",
                          "Este episódio não existe no TVMaze. Verifica a temporada e o número.",
                          "This episode isn't on TVMaze. Check the season and number.")
            case "rate_limited":
                return tr("Слишком часто. Подожди минуту и попробуй снова.",
                          "Demasiados pedidos. Espera um minuto e tenta de novo.",
                          "Too many requests. Wait a minute and try again.")
            case "invalid_code":
                return tr("Код выглядит иначе: RECAP-XXXX-XXXX-XXXX-XXXX.",
                          "O código tem outro formato: RECAP-XXXX-XXXX-XXXX-XXXX.",
                          "Codes look like RECAP-XXXX-XXXX-XXXX-XXXX.")
            case "code_not_valid":
                return tr("Код не подходит: он неверный, уже использован или истёк.",
                          "O código não serve: está errado, já foi usado ou expirou.",
                          "This code doesn't work: it's wrong, used or expired.")
            case "subscription_not_active", "subscription_not_found", "subscription_not_valid":
                return tr("Активная подписка не найдена.", "Não foi encontrada uma subscrição ativa.",
                          "No active subscription found.")
            case "turns_tampered":
                return tr("Разговор сбился. Начни его заново.", "A conversa baralhou-se. Começa de novo.",
                          "The chat got out of sync. Start it again.")
            case "conversation_over":
                return tr("Разговор окончен — начни новый.", "A conversa terminou — começa outra.",
                          "The chat is over — start a new one.")
            case "model_busy", "model_unavailable", "tvmaze_unavailable", "appstore_unavailable":
                return tr("Сервис сейчас занят. Попробуй через минуту.",
                          "O serviço está ocupado. Tenta daqui a um minuto.",
                          "The service is busy. Try again in a minute.")
            case "model_refused", "model_truncated", "model_error":
                return tr("Модель не справилась с этим запросом. Попробуй ещё раз.",
                          "O modelo não conseguiu responder. Tenta de novo.",
                          "The model couldn't handle this request. Try again.")
            case "unauthorized":
                return tr("Сервер не узнал устройство. Попробуй ещё раз.",
                          "O servidor não reconheceu o dispositivo. Tenta de novo.",
                          "The server didn't recognize this device. Try again.")
            default:
                return tr("Сервер ответил ошибкой (\(code)).", "O servidor respondeu com um erro (\(code)).",
                          "The server returned an error (\(code)).")
            }
        }
    }
}
