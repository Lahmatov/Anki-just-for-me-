import Foundation
import SwiftData
import Observation
import AJFMCore

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

    init(context: ModelContext) {
        self.context = context
    }

    var subtitleSummary: String? {
        guard let track else { return nil }
        let minutes = Int(track.duration / 60)
        return "\(track.cues.count) реплик, \(minutes) минут"
    }

    var canAnalyze: Bool {
        track != nil && transcript.split(whereSeparator: { $0.isWhitespace }).count >= 10
    }

    /// Оценка стоимости разбора до отправки — чтобы не было сюрпризов.
    var estimatedCost: Double {
        guard let track else { return 0 }
        let input = RetellPrompt.estimateTokens(subtitleText(from: track))
            + RetellPrompt.estimateTokens(transcript)
            + RetellPrompt.estimateTokens(RetellPrompt.system)
        return ClaudeModel.pricing(for: selectedModel)
            .cost(inputTokens: input, outputTokens: 1_500)
    }

    var selectedModel: String {
        UserDefaults.standard.string(forKey: SettingsKey.claudeModel) ?? ClaudeModel.opus5.id
    }

    var monthlyLimit: Double {
        let stored = UserDefaults.standard.double(forKey: SettingsKey.monthlyBudget)
        return stored > 0 ? stored : 10
    }

    var usage: UsageSummary {
        let records = ((try? context.fetch(FetchDescriptor<UsageEntry>())) ?? [])
            .map(\.asRecord)
        return UsageTracker.summary(records: records, limit: monthlyLimit)
    }

    // MARK: - Субтитры

    func loadSubtitles(from data: Data) {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            step = .failed("Не удалось прочитать файл субтитров.")
            return
        }
        do {
            let parsed = try SubtitleParser.parse(raw)
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
                step = .failed("Нужны разрешения на микрофон и распознавание речи.")
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
        guard let track else { return }
        guard let apiKey = Keychain.get(Keychain.claudeAPIKey), !apiKey.isEmpty else {
            step = .failed(ClaudeClientError.noAPIKey.localizedDescription)
            return
        }

        let summary = usage
        let pricing = ClaudeModel.pricing(for: selectedModel)
        let inputEstimate = RetellPrompt.estimateTokens(subtitleText(from: track))
            + RetellPrompt.estimateTokens(transcript)
        guard UsageTracker.canAfford(
            estimatedInputTokens: inputEstimate, estimatedOutputTokens: 1_500,
            pricing: pricing, summary: summary) else {
            step = .failed(ClaudeClientError
                .budgetExceeded(spent: summary.monthCost, limit: summary.limit)
                .localizedDescription)
            return
        }

        step = .analyzing
        do {
            let client = ClaudeClient(apiKey: apiKey, model: selectedModel)
            let result = try await client.analyze(
                subtitles: subtitleText(from: track),
                retell: transcript,
                episodeTitle: episodeTitle.isEmpty ? nil : episodeTitle,
                watchedUpTo: watchedSeconds)

            context.insert(UsageEntry(record: result.usage))
            context.insert(RetellSession(
                episodeTitle: episodeTitle.isEmpty ? "Без названия" : episodeTitle,
                transcript: transcript,
                report: result.report,
                cost: result.usage.cost,
                model: selectedModel))
            try? context.save()

            report = result.report
            lastCost = result.usage.cost
            step = .done
        } catch {
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
        let name = episodeTitle.isEmpty ? "Пересказ" : "Пересказ: \(episodeTitle)"
        guard let file = report.makeDeck(name: name, folder: "Пересказы") else { return nil }

        let importer = ImportService(context: context)
        let plan = ImportPlanner.plan(
            file: file,
            existingTerms: (try? existingTerms()) ?? [:])
        return try? importer.apply(plan)
    }

    var deckCandidateCount: Int {
        guard let report else { return 0 }
        return report.language.suggestedWords.count + report.language.grammar.count
    }

    private func existingTerms() throws -> [String: String] {
        var map: [String: String] = [:]
        for note in try context.fetch(FetchDescriptor<Note>()) where map[note.normalizedTerm] == nil {
            map[note.normalizedTerm] = note.deck?.name ?? "без набора"
        }
        return map
    }

    func reset() {
        recorder.reset()
        transcript = ""
        report = nil
        step = track == nil ? .needsSubtitles : .ready
    }
}
