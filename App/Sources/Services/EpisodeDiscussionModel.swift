import Foundation
import SwiftData
import Observation
import AJFMCore

/// Ход разговора с Мончиком о серии.
@Observable
@MainActor
final class EpisodeDiscussionModel {

    enum Step: Equatable {
        case notStarted
        case thinking
        case waitingForAnswer
        case recording
        case finished
        case failed(String)
    }

    /// Ответ длиннее не отправляется: разговор — не сочинение, а длинный
    /// ответ съедает бюджет и уводит модель от темы.
    static let answerLimit = 600

    private(set) var turns: [EpisodeDiscussion.Turn] = []
    private(set) var step: Step = .notStarted
    private(set) var spent: Double = 0
    var draft = ""

    let episode: EpisodeContext
    let retelling: String?
    /// Сколько вопросов задаст Мончик: шесть в обычном разговоре, три в Recap.
    let questions: Int
    let recorder = RetellRecorder()
    private let context: ModelContext

    init(context: ModelContext, episode: EpisodeContext, retelling: String?,
         questions: Int = EpisodeDiscussion.maxLearnerTurns) {
        self.context = context
        self.episode = episode
        self.retelling = retelling
        self.questions = EpisodeDiscussion.clampedLimit(questions)
    }

    var questionNumber: Int {
        min(EpisodeDiscussion.learnerTurnCount(turns) + 1, questions)
    }

    var canSend: Bool {
        step == .waitingForAnswer
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var tipCount: Int { turns.compactMap(\.tip).count }

    // MARK: - Ход

    func start() async {
        guard turns.isEmpty, step == .notStarted else { return }
        await requestReply()
    }

    func send() async {
        guard canSend else { return }
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.answerLimit))
        turns.append(EpisodeDiscussion.Turn(speaker: .learner, text: text))
        draft = ""
        await requestReply()
    }

    /// Повтор после сетевой ошибки: последний ответ уже в истории.
    func retry() async {
        guard case .failed = step else { return }
        if turns.last?.speaker == .monchik { step = .waitingForAnswer; return }
        await requestReply()
    }

    private func requestReply() async {
        step = .thinking
        do {
            let result = try await AIService.discuss(
                context: context, episode: episode, turns: turns, retelling: retelling,
                questions: questions)
            turns.append(EpisodeDiscussion.Turn(
                speaker: .monchik, text: result.reply.text, tip: result.reply.tip,
                signature: result.reply.signature))
            spent += result.cost
            if UserDefaults.standard.object(forKey: SettingsKey.autoSpeak) as? Bool ?? true {
                SpeechService.shared.speak(result.reply.text)
            }
            step = result.reply.finished || EpisodeDiscussion.isLastTurn(turns, limit: questions)
                ? .finished : .waitingForAnswer
        } catch {
            Log.failure(.network, "Реплика Мончика не пришла", error)
            step = .failed(error.localizedDescription)
        }
    }

    // MARK: - Голос

    func startRecording() {
        Task {
            guard await PronunciationService.requestPermissions() else {
                step = .failed(tr("Нужны разрешения на микрофон и распознавание речи.",
                                  "São precisas permissões para o microfone e o reconhecimento de fala.",
                                  "Microphone and speech recognition permissions are needed."))
                return
            }
            SpeechService.shared.stop()
            recorder.reset()
            recorder.start()
            step = .recording
        }
    }

    func stopRecording() {
        recorder.stop()
        let spoken = recorder.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = [draft.trimmingCharacters(in: .whitespacesAndNewlines), spoken]
            .filter { !$0.isEmpty }.joined(separator: " ")
        step = .waitingForAnswer
    }

    // MARK: - Карточки

    func makeDeck() -> ImportResult? {
        guard let file = EpisodeDiscussion.deckFile(
            from: turns,
            name: tr("Разговор: ", "Conversa: ", "Chat: ") + episode.title,
            folder: tr("Пересказы", "Recontos", "Retellings")) else { return nil }
        let importer = ImportService(context: context)
        guard let plan = try? importer.makePlan(from: file) else { return nil }
        return try? importer.apply(plan)
    }
}
