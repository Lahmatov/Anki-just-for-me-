import AVFoundation
import UIKit
import AJFMCore

/// Переводит системные уведомления о звуке в `AudioEvent` (P-80): звонок,
/// отключённые наушники, смена микрофона, перезапуск аудиослужбы, уход
/// в фон. Решение, что делать, — `AudioInterruptionPolicy` в Core.
///
/// Живёт, пока идёт запись или озвучка: владелец держит ссылку, отпускает —
/// подписки снимаются.
@MainActor
final class AudioEventObserver {
    private nonisolated(unsafe) var tokens: [NSObjectProtocol] = []

    /// `engine` — для уведомления о смене конфигурации: оно приходит от
    /// конкретного движка, а не от сессии.
    init(engine: AVAudioEngine? = nil, handler: @escaping @MainActor (AudioEvent) -> Void) {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, object: Any? = nil,
                     _ map: @escaping (Notification) -> AudioEvent?) {
            tokens.append(center.addObserver(forName: name, object: object, queue: .main) { note in
                guard let event = map(note) else { return }
                MainActor.assumeIsolated { handler(event) }
            })
        }
        observe(AVAudioSession.interruptionNotification) { Self.interruption(from: $0) }
        observe(AVAudioSession.routeChangeNotification) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            return raw.flatMap(AVAudioSession.RouteChangeReason.init) == .oldDeviceUnavailable ? .deviceLost : nil
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { _ in .mediaServicesReset }
        observe(UIApplication.didEnterBackgroundNotification) { _ in .appDidEnterBackground }
        if let engine {
            observe(.AVAudioEngineConfigurationChange, object: engine) { _ in .configurationChanged }
        }
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    private nonisolated static func interruption(from note: Notification) -> AudioEvent? {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}
