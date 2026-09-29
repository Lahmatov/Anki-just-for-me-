import Foundation

/// Режим UI-тестов (`-ui-testing` в аргументах запуска).
///
/// Тест должен начинаться с чистого листа и сразу видеть главный экран:
/// база — в памяти, настройки сброшены, заставка и знакомство пропущены.
/// Иначе каждый прогон зависел бы от предыдущего и от анимации запуска.
enum UITesting {
    static let flag = "-ui-testing"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    /// `-ui-demo`: сразу со стартовым набором — для скриншотов экранов,
    /// где пустая база показала бы только заглушки.
    static var wantsDemoData: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-ui-demo")
    }

    /// До первого экрана: прошлый прогон не должен оставить ни настроек, ни языка.
    static func prepare() {
        guard isActive, let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
