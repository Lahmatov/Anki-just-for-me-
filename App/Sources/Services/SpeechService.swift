import Foundation
import AVFoundation
import Observation
import AJFMCore

/// Озвучка через системный синтезатор: бесплатно, офлайн, без интернета.
///
/// Голос выбирается явно лучшим из доступных — если этого не делать, система
/// молча берёт сжатый compact, и слово звучит роботом. Логика выбора живёт
/// в ядре и покрыта тестами, здесь только мост к AVFoundation.
@Observable
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    /// Показывать ли подсказку про скачивание голоса получше.
    var shouldSuggestBetterVoice: Bool {
        VoiceSelector.shouldSuggestBetterVoice(from: availableVoices, language: language)
    }

    var voiceName: String? {
        VoiceSelector.best(from: availableVoices, language: language)?.name
    }

    private let language = "en-US"

    private var availableVoices: [VoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            VoiceDescriptor(
                identifier: voice.identifier,
                language: voice.language,
                quality: Self.quality(of: voice),
                name: voice.name)
        }
    }

    private static func quality(of voice: AVSpeechSynthesisVoice) -> VoiceQuality {
        switch voice.quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .compact
        }
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        guard let best = VoiceSelector.best(from: availableVoices, language: language) else {
            return AVSpeechSynthesisVoice(language: language)
        }
        return AVSpeechSynthesisVoice(identifier: best.identifier)
            ?? AVSpeechSynthesisVoice(language: language)
    }

    func speak(_ text: String, rate: SpeechRate = .normal) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate.multiplier
        // Небольшая пауза в конце — иначе последний звук слова обрезается.
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        synthesizer.speak(utterance)
        // Синтезатор не даёт простого признака завершения без делегата,
        // а точность здесь не важна: флаг нужен только для подсветки кнопки.
        Task {
            try? await Task.sleep(for: .seconds(estimatedDuration(of: trimmed, rate: rate)))
            isSpeaking = false
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func estimatedDuration(of text: String, rate: SpeechRate) -> Double {
        let words = max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
        return Double(words) * 0.45 / Double(rate.multiplier)
    }

    /// Озвучка должна звучать даже в беззвучном режиме — иначе карточка на
    /// аудирование молча «не работает», и непонятно почему.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }
}
