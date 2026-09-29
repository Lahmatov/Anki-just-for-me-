import Foundation
import SwiftData
import Observation
import AJFMCore

/// Серия, с экрана которой начат пересказ или разговор.
struct EpisodeContext: Equatable, Hashable {
    var showID: Int
    var showName: String
    var episode: EpisodeInfo

    /// «Friends S01E03 · The One with the Thumb».
    var title: String { "\(showName) \(episode.title)" }

    var synopsis: String? {
        episode.summary.isEmpty ? nil : episode.summary
    }
}

/// Состояние процесса «пересказал серию — получил разбор».
@Observable
@MainActor
final class RetellFlowModel {

    enum Step: Equatable {
        case needsSubtitles
        case ready
        case recording
        case editingTranscript
        case analyzing
        case done
        case failed(String)
    }

    private(set) var step: Step = .needsSubtitles
    private(set) var track: SubtitleTrack?
    private(set) var report: RetellReport?
    private(set) var lastCost: Double = 0

    var episodeTitle = ""
    var transcript = ""
    /// До какой минуты досмотрено — защита от спойлеров в разборе.
    var watchedUpToMinutes: Double = 0

    let recorder = RetellRecorder()
    private let context: ModelContext
    /// Серия, если пересказ начат с её экрана: даёт название и описание-эталон.
    let episode: EpisodeContext?

    init(context: ModelContext, episode: EpisodeContext? = nil) {
        self.context = context
        self.episode = episode
        if let episode {
            episodeTitle = episode.title
            // Есть описание серии — можно начинать сразу, без поиска субтитров.
            if episode.synopsis != nil { step = .ready }
        }
    }

    /// С чем сверять пересказ: субтитры точнее, описание — если субтитров нет.
    var reference: RetellReference? {
        if let track { return .subtitles(subtitleText(from: track)) }
        if let synopsis = episode?.synopsis { return .synopsis(synopsis) }
        return nil
    }

    var subtitleSummary: String? {
        guard let track else { return nil }
        let minutes = Int(track.duration / 60)
        return trCount(track.cues.count, ru: ("реплика", "реплики", "реплик"),
                       pt: ("fala", "falas"), en: ("line", "lines"))
            + ", " + Counted.minutes(minutes)
    }

    var canAnalyze: Bool {
        reference != nil && transcript.split(whereSeparator: { $0.isWhitespace }).count >= 10
    }

    /// Оценка стоимости разбора до отправки — чтобы не было сюрпризов.
    var estimatedCost: Double {
        guard let reference else { return 0 }
        let input = RetellPrompt.estimateTokens(reference.text)
            + RetellPrompt.estimateTokens(transcript)
            + RetellPrompt.estimateTokens(RetellPrompt.system)
        return ClaudeModel.pricing(for: selectedModel)
            .cost(inputTokens: input, outputTokens: RetellPrompt.estimatedOutputTokens)
    }

    var selectedModel: String { ClaudeBudget(context: context).model.id }

    var monthlyLimit: Double { ClaudeBudget(context: context).monthlyLimit }

    var usage: UsageSummary { ClaudeBudget(context: context).usage }

    // MARK: - Субтитры

    func loadSubtitles(from data: Data) {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            step = .failed(tr("Не удалось прочитать файл субтитров.",
                              "Não foi possível ler o ficheiro de legendas.",
                              "Couldn't read the subtitle file."))
            return
        }
        do {
            let parsed = try SubtitleParser.parse(raw)
            Log.info(
                .importing, "Субтитры загружены",
                detail: "реплик: \(parsed.cues.count), "
                    + "длительность: \(Int(parsed.duration / 60)) мин")
            track = parsed
            watchedUpToMinutes = (parsed.duration / 60).rounded()
            step = .ready
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    // MARK: - Запись

    func startRecording() {
        Task {
            guard await PronunciationService.requestPermissions() else {
                step = .failed(tr("Нужны разрешения на микрофон и распознавание речи.",
                                  "São precisas permissões para o microfone e o reconhecimento de fala.",
                                  "Microphone and speech recognition permissions are needed."))
                return
            }
            recorder.reset()
            recorder.start()
            step = .recording
        }
    }

    func stopRecording() {
        recorder.stop()
        transcript = recorder.fullText
        step = .editingTranscript
    }

    // MARK: - Разбор

    func analyze() async {
        guard let reference else { return }
        guard let apiKey = Keychain.get(Keychain.claudeAPIKey), !apiKey.isEmpty else {
            // Разбор пересказа в Recap Plus не входит: подписка — только на слова
            // к сериям и разговор о них. Там и проверяется понимание серии.
            step = .failed(RecapAccount.shared.usesBackend
                ? tr("Разбор пересказа работает со своим ключом Claude. С Recap Plus расскажи "
                        + "о серии Мончику — кнопка «Поговорить с Мончиком» на экране серии.",
                     "A análise do reconto funciona com a tua chave do Claude. Com o Recap Plus, "
                        + "conta o episódio ao Monchik — botão «Conversar com o Monchik».",
                     "Retelling reviews need your own Claude key. With Recap Plus, tell Monchik "
                        + "about the episode — the “Chat with Monchik” button on the episode.")
                : ClaudeClientError.noAPIKey.localizedDescription)
            return
        }

        let summary = usage
        let pricing = ClaudeModel.pricing(for: selectedModel)
        let inputEstimate = RetellPrompt.estimateTokens(reference.text)
            + RetellPrompt.estimateTokens(transcript)
        guard UsageTracker.canAfford(
            estimatedInputTokens: inputEstimate,
            estimatedOutputTokens: RetellPrompt.estimatedOutputTokens,
            pricing: pricing, summary: summary) else {
            step = .failed(ClaudeClientError
                .budgetExceeded(spent: summary.monthCost, limit: summary.limit)
                .localizedDescription)
            return
        }

        step = .analyzing
        do {
            let client = ClaudeClient(apiKey: apiKey, model: selectedModel)
            let outcome = try await client.analyze(
                reference: reference,
                retell: transcript,
                episodeTitle: episodeTitle.isEmpty ? nil : episodeTitle,
                watchedUpTo: watchedSeconds)

            // Расход записываем в любом случае: запрос оплачен независимо
            // от того, удалось ли разобрать ответ.
            let budget = ClaudeBudget(context: context)
            budget.record(outcome.usage, purpose: "Разбор пересказа")
            lastCost = outcome.usage.cost

            guard let parsed = outcome.report else {
                Log.error(
                    .network, "Ответ модели не разобрался",
                    detail: outcome.decodeError ?? "причина неизвестна")
                let reason = outcome.decodeError
                    ?? tr("неизвестная причина", "motivo desconhecido", "unknown reason")
                step = .failed(tr(
                    "Модель ответила, но разобрать ответ не вышло: \(reason). "
                        + "Деньги за запрос уже учтены.",
                    "O modelo respondeu, mas não foi possível ler a resposta: \(reason). "
                        + "O custo do pedido já foi contabilizado.",
                    "The model replied, but the reply couldn't be read: \(reason). "
                        + "The request's cost has already been counted."))
                return
            }

            let session = RetellSession(
                episodeTitle: episodeTitle.isEmpty
                    ? tr("Без названия", "Sem título", "Untitled")
                    : episodeTitle,
                transcript: transcript,
                report: parsed,
                cost: outcome.usage.cost,
                model: selectedModel)
            session.showID = episode?.showID
            session.episodeKeyRaw = episode?.episode.key.raw
            context.insert(session)
            try? context.save()

            report = parsed
            step = .done
        } catch {
            Log.failure(.network, "Запрос разбора не прошёл", error)
            step = .failed(error.localizedDescription)
        }
    }

    /// Субтитры до момента, до которого досмотрено.
    private func subtitleText(from track: SubtitleTrack) -> String {
        track.plainText(upTo: watchedSeconds)
    }

    private var watchedSeconds: TimeInterval? {
        guard let track, watchedUpToMinutes > 0 else { return nil }
        let seconds = watchedUpToMinutes * 60
        return seconds >= track.duration ? nil : seconds
    }

    // MARK: - Ошибки в карточки

    /// Замыкает главный контур: разбор превращается в набор карточек.
    @discardableResult
    func makeDeck() -> ImportResult? {
        guard let report else { return nil }
        let retelling = tr("Пересказ", "Reconto", "Retelling")
        let name = episodeTitle.isEmpty ? retelling : "\(retelling): \(episodeTitle)"
        let folder = tr("Пересказы", "Recontos", "Retellings")
        guard let file = report.makeDeck(name: name, folder: folder) else { return nil }

        let importer = ImportService(context: context)
        guard let plan = try? importer.makePlan(from: file) else { return nil }
        return try? importer.apply(plan)
    }

    var deckCandidateCount: Int {
        guard let report else { return 0 }
        return report.language.suggestedWords.count + report.language.grammar.count
    }


    func reset() {
        recorder.reset()
        transcript = ""
        report = nil
        step = reference == nil ? .needsSubtitles : .ready
    }
}
