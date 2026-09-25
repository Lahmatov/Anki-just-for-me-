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

/// Значок строки списка: символ на цветной плашке, как в системных настройках.
///
/// Голые серые значки делают списки одинаковыми; цветная плашка даёт глазу
/// якорь и различает разделы, не добавляя текста.
struct IconBadge: View {
    let systemName: String
    var color: Color = .accentColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// Строка-переход в виде карточки для экранов из карточек, а не списков.
struct CardLink<Destination: View>: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var color: Color = .accentColor
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                IconBadge(systemName: systemImage, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Заголовок блока на экранах из карточек — в одном стиле со списками.
struct CardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
