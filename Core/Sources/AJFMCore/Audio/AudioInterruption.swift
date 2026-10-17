import Foundation

/// Что система сделала со звуком (P-80). Приложение переводит системные
/// уведомления аудиосессии и приложения в эти события — правило реакции здесь,
/// где его можно проверить тестом без микрофона.
public enum AudioEvent: Equatable, Sendable {
    /// Звонок, FaceTime, будильник, Siri: система забрала звук.
    case interruptionBegan
    /// Прерывание кончилось; `shouldResume` — система разрешает продолжить.
    case interruptionEnded(shouldResume: Bool)
    /// Гарнитура или AirPods отключились: пропал микрофон или наушники.
    case deviceLost
    /// Формат входа поменялся (другой микрофон) — движок остановлен системой.
    case configurationChanged
    /// Аудиослужба iOS перезапустилась — всё звуковое надо собрать заново.
    case mediaServicesReset
    /// Приложение ушло в фон: без фонового режима микрофон отключается.
    case appDidEnterBackground

    /// Короткое имя для журнала.
    public var logName: String {
        switch self {
        case .interruptionBegan: return "interruption"
        case .interruptionEnded: return "interruption-ended"
        case .deviceLost: return "device-lost"
        case .configurationChanged: return "configuration"
        case .mediaServicesReset: return "media-reset"
        case .appDidEnterBackground: return "background"
        }
    }
}

public enum AudioReaction: Equatable, Sendable {
    case ignore
    /// Остановить запись и оставить уже распознанное: пересказ на две минуты
    /// не должен пропасть из-за звонка.
    case finishKeepingText
    /// Замолчать: озвучка поверх разговора или после выдернутых наушников
    /// на весь вагон хуже тишины.
    case stopPlayback
}

public enum AudioInterruptionPolicy {
    /// После прерывания запись сама не возобновляется даже с разрешения
    /// системы: включить микрофон без нажатия — сюрприз для человека,
    /// который только что говорил по телефону.
    public static func reaction(to event: AudioEvent, isRecording: Bool, isPlaying: Bool) -> AudioReaction {
        if isRecording {
            switch event {
            case .interruptionBegan, .deviceLost, .configurationChanged, .mediaServicesReset,
                 .appDidEnterBackground:
                return .finishKeepingText
            case .interruptionEnded:
                return .ignore
            }
        }
        if isPlaying {
            switch event {
            case .interruptionBegan, .deviceLost, .mediaServicesReset, .appDidEnterBackground:
                return .stopPlayback
            case .interruptionEnded, .configurationChanged:
                return .ignore
            }
        }
        return .ignore
    }
}
