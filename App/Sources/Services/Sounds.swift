import AVFoundation
import AJFMCore

/// Короткие звуки: верный ответ, ошибка, праздник, подарок.
///
/// Сессия `.ambient`: звуки смешиваются с музыкой и подкастом и молчат,
/// когда телефон на беззвучном, — приложение для учёбы в метро не должно
/// звенеть на весь вагон. Выключаются в настройках.
@MainActor
enum Sounds {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
    private static var started = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.soundsEnabled) as? Bool ?? true
    }

    static func play(_ cue: SoundCue) {
        guard isEnabled, !UITesting.isActive, let buffer = buffer(for: cue), start() else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Двигатель запускается при первом звуке, а не при старте приложения:
    /// кто звуки выключил, тот и аудиосессию не поднимает.
    private static func start() -> Bool {
        if started, engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if !started {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                started = true
            }
            try engine.start()
            return true
        } catch {
            Log.failure(.app, "Звук не включился", error)
            return false
        }
    }

    private static let format = AVAudioFormat(
        standardFormatWithSampleRate: ToneSynth.sampleRate, channels: 1)!

    /// Звук синтезируется один раз и дальше берётся из памяти.
    private static func buffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue] { return cached }
        let samples = ToneSynth.render(cue.tones)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffers[cue] = buffer
        return buffer
    }
}
