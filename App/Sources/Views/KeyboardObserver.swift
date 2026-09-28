import SwiftUI
import UIKit
import Observation

/// Видна ли клавиатура — чтобы прятать панель вкладок, пока печатаешь.
@Observable
@MainActor
final class KeyboardObserver {
    private(set) var isVisible = false

    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = true }
        })
        tokens.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = false }
        })
    }
}
