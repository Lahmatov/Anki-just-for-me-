import Foundation
import SwiftData
import Observation
import AJFMCore

/// «Сделай набор по Friends 1x03» — прямо из приложения, без чата.
@Observable
@MainActor
final class DeckRequestModel {

    enum Step: Equatable {
        case editing
        case working
        case failed(String)
    }

    var topic = ""
    var wordCount = DeckRequest.defaultWordCount
    var level: CEFRLevel? = AppSettings.englishLevel
    private(set) var subtitles: String?
    private(set) var subtitlesName: String?
    private(set) var step: Step = .editing
    private(set) var lastCost: Double = 0

    /// Серия, если набор просят с её экрана: номер уже известен, искать не нужно.
    var episode: EpisodeContext?
    private let context: ModelContext
    /// Читается один раз: оценка цены пересчитывается на каждую букву в поле,
    /// и ходить за сотнями слов в базу при каждом нажатии незачем.
    private let knownTerms: [String]

    init(context: ModelContext) {
        self.context = context
        self.knownTerms = ImportService(context: context)
            .recentTerms(limit: DeckRequest.knownTermsLimit)
    }

    private var budget: ClaudeBudget { ClaudeBudget(context: context) }

    var hasAPIKey: Bool { budget.apiKey != nil }

    /// Через сервер Recap: подписка активна или своего ключа нет, а к серии
    /// может найтись бесплатный готовый набор из каталога.
    var usesBackend: Bool {
        RecapAccount.shared.usesBackend || (!hasAPIKey && RecapBackend.isConfigured)
    }

    var request: DeckRequest {
        DeckRequest(
            topic: topic, subtitles: subtitles, wordCount: wordCount, level: level,
            language: AppSettings.language, knownTerms: knownTerms)
    }

    var canSubmit: Bool {
        step != .working && (episode != nil
                             || !topic.trimmingCharacters(in: .whitespaces).isEmpty
                             || subtitles != nil)
    }

    /// Оценка до отправки, чтобы цена не была сюрпризом.
    var estimatedCost: Double {
        let request = self.request
        return budget.deckModel.cost(
            inputTokens: request.estimatedInputTokens,
            outputTokens: request.estimatedOutputTokens)
    }

    var usage: UsageSummary { budget.usage }

    // MARK: - Субтитры

    func loadSubtitles(from data: Data, name: String) {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            step = .failed(tr("Не удалось прочитать файл субтитров.",
                              "Não foi possível ler o ficheiro de legendas.",
                              "Couldn't read the subtitle file."))
            return
        }
        // Таймкоды модели не нужны и стоят денег — оставляем только реплики.
        // Если формат не распознался, отдаём текст как есть: это может быть
        // просто скопированный диалог.
        subtitles = (try? SubtitleParser.parse(raw))?.plainText() ?? raw
        subtitlesName = name
        if step != .working { step = .editing }
    }

    func removeSubtitles() {
        subtitles = nil
        subtitlesName = nil
    }

    // MARK: - Через сервер

    /// Набор через сервер Recap. Сервер принимает только номер серии —
    /// поэтому свободная тема («слова для собеседования») здесь не пройдёт:
    /// так подписка тратится только на сериалы.
    private func generateOnServer() async -> ImportPlan? {
        step = .working
        do {
            let target: (showID: Int, season: Int, episode: Int, show: String)
            if let episode {
                target = (episode.showID, episode.episode.season, episode.episode.number,
                          episode.showName)
            } else if let ref = EpisodeRef.parse(topic),
                      let showID = await TVMazeClient().lookup(ref).showID {
                target = (showID, ref.season, ref.episode, ref.show)
            } else {
                step = .failed(tr("С Recap Plus наборы — к сериям. Напиши, например, «Friends 1x03», "
                                    + "или открой серию во вкладке «Сериалы».",
                                  "Com o Recap Plus, os baralhos são de episódios. Escreve, por exemplo, "
                                    + "«Friends 1x03», ou abre o episódio no separador «Séries».",
                                  "With Recap Plus decks are for episodes. Type e.g. “Friends 1x03”, "
                                    + "or open the episode on the Shows tab."))
                return nil
            }
            let response = try await RecapBackend.shared.deck(BackendAPI.DeckBody(
                showId: target.showID, season: target.season, episode: target.episode,
                language: AppSettings.language, level: level, wordCount: wordCount,
                knownTerms: knownTerms, subtitles: subtitles))
            RecapAccount.shared.update(response.plan)
            var file = response.deck
            if file.deck.cover == nil, let episode {
                // Постер уже есть у сериала на телефоне — не нужно спрашивать снова.
                file.deck.cover = ShowService(context: context).tracked(id: episode.showID)?.posterURL
            }
            let plan = try ImportService(context: context).makePlan(from: file)
            Log.info(.importing, "Набор с сервера получен",
                     detail: "«\(file.deck.name)», слов: \(file.notes.count), \(response.source)")
            step = .editing
            return plan
        } catch let failure as BackendAPI.Failure {
            // Нет подписки, но есть свой ключ — делаем по-старому, напрямую.
            if failure.needsPlan, hasAPIKey, !RecapAccount.shared.usesBackend {
                step = .editing
                return await generateDirectly()
            }
            needsPlan = failure.needsPlan
            step = .failed(failure.localizedDescription)
            return nil
        } catch {
            step = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Сервер ответил «нужна подписка» — экран покажет кнопку Recap Plus.
    private(set) var needsPlan = false

    // MARK: - Запрос

    /// Возвращает план импорта для обычного превью или nil при ошибке
    /// (причина — в `step`).
    func generate() async -> ImportPlan? {
        // Кнопка гаснет только после перерисовки, а два быстрых нажатия
        // успевают запустить две задачи — и два платных запроса.
        guard step != .working else { return nil }
        if usesBackend {
            return await generateOnServer()
        }
        return await generateDirectly()
    }

    /// Напрямую в Anthropic по своему ключу.
    private func generateDirectly() async -> ImportPlan? {
        let request = self.request
        do {
            try request.validate()
        } catch {
            step = .failed(error.localizedDescription)
            return nil
        }
        guard let apiKey = budget.apiKey else {
            step = .failed(ClaudeClientError.noAPIKey.localizedDescription)
            return nil
        }
        let model = budget.deckModel
        let estimate = model.cost(
            inputTokens: request.estimatedInputTokens,
            outputTokens: request.estimatedOutputTokens)
        guard budget.usage.monthCost + estimate <= budget.monthlyLimit else {
            let summary = budget.usage
            step = .failed(ClaudeClientError
                .budgetExceeded(spent: summary.monthCost, limit: summary.limit)
                .localizedDescription)
            return nil
        }

        step = .working
        do {
            let completion = try await ClaudeClient(apiKey: apiKey, model: model.id)
                .complete(ClaudeRequest(
                    model: model,
                    system: request.system,
                    userMessage: request.userMessage,
                    maxTokens: DeckRequest.maxTokens,
                    // Подбор слов — не головоломка: низкого усилия хватает,
                    // а ответ приходит заметно быстрее (у Haiku усилия нет вовсе).
                    effort: .low,
                    outputSchemaJSON: DeckRequest.outputSchemaJSON))

            budget.record(completion.usage, purpose: "Набор по запросу")
            lastCost = completion.usage.cost

            if let problem = ClaudeClient.problem(with: completion) {
                step = .failed(problem)
                return nil
            }
            let text = completion.text ?? ""
            var file = try request.deckFile(fromResponse: text)
            // Серия — ищем постер и настоящее название серии. Не нашлось —
            // набор всё равно уже разложен по папкам сериала.
            if let episode = request.episode(fromResponse: text) {
                let info = await TVMazeClient().lookup(episode)
                file = DeckRequest.decorate(
                    file, episode: episode, title: info.title, poster: info.poster)
            }
            let plan = try ImportService(context: context).makePlan(from: file)
            Log.info(
                .importing, "Набор от Claude получен",
                detail: "«\(file.deck.name)», слов: \(file.notes.count)")
            step = .editing
            return plan
        } catch {
            Log.failure(.network, "Набор по запросу не получился", error)
            step = .failed(error.localizedDescription)
            return nil
        }
    }
}
