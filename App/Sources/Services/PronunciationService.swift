import Foundation
import AVFoundation
import Speech
import Observation
import AJFMCore

/// Запись голоса и распознавание речи на устройстве.
///
/// Распознавание идёт локально (`requiresOnDeviceRecognition`): без интернета,
/// без отправки голоса куда-либо и без лимитов. Запись сохраняется в файл —
/// он нужен для шэдоуинга: послушать себя рядом с эталоном честнее любой
/// автоматической оценки.
@Observable
@MainActor
final class PronunciationService {

    enum Status: Equatable {
        case idle
        case recording
        case processing
        case finished(PronunciationAssessment)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Что распознаётся прямо сейчас — показывается по ходу записи.
    private(set) var partialText = ""
    private(set) var recordingURL: URL?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?

    private var expected = ""
    private var pair: MinimalPair?
    private var player: AVAudioPlayer?
    private var bestTranscript = ""
    private var bestConfidence: Double = 0

    var isRecording: Bool { status == .recording }

    // MARK: - Разрешения

    /// Нужны оба: микрофон и распознавание речи. Без внятного текста в Info.plist
    /// система просто не покажет запрос.
    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Запись

    func start(expecting word: String, pair: MinimalPair? = nil) {
        guard status != .recording else { return }
        self.expected = word
        self.pair = pair
        partialText = ""
        bestTranscript = ""
        bestConfidence = 0

        guard let recognizer, recognizer.isAvailable else {
            status = .failed("Распознавание английской речи недоступно на этом устройстве.")
            return
        }

        do {
            try configureSession()
            try startEngine(with: recognizer)
            status = .recording
        } catch {
            cleanUp()
            status = .failed("Не получилось начать запись: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard status == .recording else { return }
        status = .processing
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // Распознаватель досылает финальный результат сам — он придёт
        // в обработчик задачи и завершит оценку.
    }

    /// Послушать себя. Шэдоуинг — сравнение своей записи с эталоном —
    /// даёт более честное представление о произношении, чем любая
    /// автоматическая оценка на устройстве.
    func playRecording() {
        guard let recordingURL else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: recordingURL)
        player?.play()
    }

    var hasRecording: Bool { recordingURL != nil }

    func reset() {
        cleanUp()
        status = .idle
        partialText = ""
    }

    // MARK: - Внутреннее

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startEngine(with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Локально: без интернета, без отправки голоса и без лимитов запросов.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ajfm-recording.caf")
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            try? self?.audioFile?.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let transcript = result.bestTranscription.formattedString
            partialText = transcript
            if !transcript.isEmpty {
                bestTranscript = transcript
                bestConfidence = averageConfidence(of: result)
            }
            if result.isFinal {
                finish()
                return
            }
        }
        if error != nil, status == .processing {
            // Ошибка после остановки обычно значит «речи не было» —
            // это не сбой, а пустая попытка.
            finish()
        } else if error != nil, status == .recording {
            cleanUp()
            status = .failed("Распознавание прервалось. Попробуй ещё раз.")
        }
    }

    /// Уверенность считаем по сегментам: единой оценки распознаватель не даёт.
    private func averageConfidence(of result: SFSpeechRecognitionResult) -> Double {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 0 }
        let sum = segments.reduce(0.0) { $0 + Double($1.confidence) }
        return sum / Double(segments.count)
    }

    private func finish() {
        let assessment: PronunciationAssessment
        if let pair {
            assessment = MinimalPairLibrary.evaluate(
                pair: pair, target: expected,
                recognized: bestTranscript, confidence: bestConfidence)
        } else {
            assessment = PronunciationEvaluator.evaluate(
                expected: expected, recognized: bestTranscript, confidence: bestConfidence)
        }
        cleanUp()
        status = .finished(assessment)
    }

    private func cleanUp() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        audioFile = nil
    }
}
