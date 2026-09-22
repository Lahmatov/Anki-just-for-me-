import Foundation
import AVFoundation
import Speech
import Observation
import AJFMCore

/// Запись и расшифровка длинного пересказа.
///
/// Распознаватель речи не рассчитан на несколько минут подряд, поэтому
/// расшифровка идёт отрезками: аудио пишется в один файл непрерывно, а
/// распознавание перезапускается каждые 50 секунд, накапливая текст.
/// Всё локально — голос никуда не отправляется.
@Observable
@MainActor
final class RetellRecorder {

    enum Status: Equatable {
        case idle
        case recording
        case finished
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Накопленный текст пересказа.
    private(set) var transcript = ""
    /// Текущий, ещё не завершённый отрезок.
    private(set) var partial = ""
    private(set) var elapsed: TimeInterval = 0

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var segmentStart = Date()
    /// Номер текущего отрезка. Старая задача распознавания может прислать
    /// финальный результат уже после того, как отрезок перенесён в текст —
    /// без этой проверки кусок попадал бы в расшифровку дважды.
    private var segmentGeneration = 0

    /// Больше минуты распознаватель не держит — перезапускаем отрезок заранее.
    private let segmentLimit: TimeInterval = 50

    var isRecording: Bool { status == .recording }

    var fullText: String {
        [transcript, partial]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    var wordCount: Int {
        fullText.split(whereSeparator: { $0.isWhitespace }).count
    }

    func start() {
        guard status != .recording else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = .failed("Распознавание английской речи недоступно.")
            return
        }

        transcript = ""
        partial = ""
        elapsed = 0

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ajfm-retell.caf")
            // Собственная ссылка на файл: замыкание работает на аудиопотоке,
            // а свойство обнуляется на главном акторе.
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            audioFile = file

            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                try? file.write(from: buffer)
            }
            engine.prepare()
            try engine.start()

            startSegment(with: recognizer)
            startTimer()
            status = .recording
        } catch {
            cleanUp()
            status = .failed("Не получилось начать запись: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard status == .recording else { return }
        timer?.invalidate()
        timer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        finishSegment()
        cleanUp()
        status = .finished
    }

    func reset() {
        cleanUp()
        transcript = ""
        partial = ""
        elapsed = 0
        status = .idle
    }

    // MARK: - Отрезки

    private func startSegment(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        segmentStart = Date()
        segmentGeneration += 1
        let generation = segmentGeneration

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            Task { @MainActor in
                guard let self, let result, generation == self.segmentGeneration else {
                    return
                }
                self.partial = result.bestTranscription.formattedString
            }
        }
    }

    /// Переносит текущий отрезок в общий текст и начинает новый.
    private func rollSegment() {
        guard let recognizer, status == .recording else { return }
        finishSegment()
        startSegment(with: recognizer)
    }

    private func finishSegment() {
        // Поколение растёт сразу: всё, что придёт из старой задачи после
        // этого момента, относится к уже перенесённому отрезку.
        segmentGeneration += 1
        request?.endAudio()
        task?.finish()
        if !partial.isEmpty {
            transcript = transcript.isEmpty ? partial : transcript + " " + partial
            partial = ""
        }
        task = nil
        request = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.status == .recording else { return }
                self.elapsed += 1
                if Date().timeIntervalSince(self.segmentStart) >= self.segmentLimit {
                    self.rollSegment()
                }
            }
        }
    }

    private func cleanUp() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        request = nil
        audioFile = nil
    }
}
