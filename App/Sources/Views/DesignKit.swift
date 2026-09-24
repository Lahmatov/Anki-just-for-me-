import SwiftUI
import UIKit

/// Общие примитивы оформления.
///
/// Приложение сознательно живёт на системных компонентах: они бесплатно дают
/// тёмную тему, крупный шрифт и доступность. Здесь — только то, чего в системе
/// нет: поверхность карточки, отклик и пара правил про цвет.
///
/// Правила, которым подчиняется всё остальное:
/// 1. Цвет означает смысл (верно, ошибка, зрелость), а не украшает.
/// 2. На экране одно очевидное действие; всё прочее — тише и мельче.
/// 3. Учат обычно одной рукой и на ходу, поэтому главные кнопки крупные и внизу.
enum Design {
    static let cardCornerRadius: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let stackSpacing: CGFloat = 16

    /// Цвет состояния карточки — один и тот же во всех экранах.
    static func color(for state: LearningStateColor) -> Color {
        switch state {
        case .new: return .blue
        case .learning: return .orange
        case .review: return .green
        case .mature: return .mint
        }
    }

    enum LearningStateColor { case new, learning, review, mature }
}

/// Поверхность карточки: мягкий фон и граница вместо тени — тень на тёмной
/// теме выглядит грязно.
struct CardSurface: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        emphasized ? Color.accentColor.opacity(0.4) : Color(.separator),
                        lineWidth: emphasized ? 1.5 : 0.5))
    }
}

extension View {
    func cardSurface(emphasized: Bool = false) -> some View {
        modifier(CardSurface(emphasized: emphasized))
    }
}

/// Тактильный отклик.
///
/// На карточках он несёт смысл: подтверждение приходит раньше, чем глаз
/// дочитает текст, и по нему понятно, засчитан ответ или нет, не глядя.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
