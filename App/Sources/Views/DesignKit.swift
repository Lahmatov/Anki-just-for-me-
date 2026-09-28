import SwiftUI
import UIKit

/// Общие примитивы оформления — игровой стиль обучающих приложений
/// (Duolingo, Busuu, Speak): светлый фон, белые карточки с серой рамкой
/// и «губой» снизу, толстые скруглённые кнопки, которые вдавливаются при
/// нажатии, крупный скруглённый шрифт Nunito и маскот — лось Мончик.
/// Подробности — docs/design.md.
///
/// Правила, которым подчиняется всё остальное:
/// 1. Цвет означает смысл (верно, ошибка, зрелость), а не украшает.
/// 2. На экране одно очевидное действие; всё прочее — тише и мельче.
/// 3. Учат обычно одной рукой и на ходу, поэтому главные кнопки крупные и внизу.
enum Design {
    static let cardPadding: CGFloat = 18
    static let stackSpacing: CGFloat = 18
    static let cornerRadius: CGFloat = 18

    /// Цвет состояния карточки — один и тот же во всех экранах.
    static func color(for state: LearningStateColor) -> Color {
        switch state {
        case .new: return Theme.blue
        case .learning: return Theme.orange
        case .review: return Theme.green
        case .mature: return .mint
        }
    }

    enum LearningStateColor { case new, learning, review, mature }
}

/// Цвета темы. Основные живут в каталоге ассетов со светлым и тёмным
/// вариантом, контраст проверяет tools/make_theme.py. Яркие акценты
/// одинаковы в обеих темах — на них лежит белый или чёрный текст крупно.
enum Theme {
    static let background = Color("ThemeBackground")
    static let surface = Color("ThemeSurface")
    static let border = Color("ThemeBorder")
    static let ink = Color("ThemeInk")
    static let muted = Color("ThemeMuted")
    static let primary = Color("ThemePrimary")
    static let primaryLip = Color("ThemePrimaryLip")
    static let onPrimary = Color("ThemeOnPrimary")
    static let tint = Color("ThemeTint")

    /// Сияние, озёра, закат над Мончетундрой и лосиная шерсть.
    static let green = Color(red: 0.16, green: 0.72, blue: 0.47)
    static let blue = Color(red: 0.11, green: 0.62, blue: 0.93)
    static let orange = Color(red: 1.00, green: 0.59, blue: 0.00)
    static let gold = Color(red: 1.00, green: 0.78, blue: 0.00)
    static let red = Color(red: 0.93, green: 0.30, blue: 0.30)
    static let purple = Color(red: 0.66, green: 0.45, blue: 0.95)
    static let moose = Color(red: 0.55, green: 0.35, blue: 0.24)

    /// Толщина рамки и высота «губы» под карточкой или кнопкой.
    static let stroke: CGFloat = 2
    static let lip: CGFloat = 4
}

/// Карточка: белая заливка, серая рамка и утолщение снизу — объём
/// без размытых теней, которые на телефоне выглядят грязно.
struct Panel: ViewModifier {
    var fill: Color = Theme.surface
    var border: Color = Theme.border
    var lip: Bool = true
    var radius: CGFloat = Design.cornerRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    if lip {
                        shape.fill(border).offset(y: Theme.lip)
                    }
                    shape.fill(fill)
                    shape.strokeBorder(border, lineWidth: Theme.stroke)
                }
            }
            .padding(.bottom, lip ? Theme.lip : 0)
    }
}

extension View {
    func panel(
        fill: Color = Theme.surface, border: Color = Theme.border,
        lip: Bool = true, radius: CGFloat = Design.cornerRadius
    ) -> some View {
        modifier(Panel(fill: fill, border: border, lip: lip, radius: radius))
    }

    /// Фон экрана со списком или формой: светлый вместо системного серого.
    func themedScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

/// Поверхность карточки. Выделенная карточка (ответ открыт) получает
/// рамку главного цвета.
struct CardSurface: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(border: emphasized ? Theme.primary : Theme.border)
    }
}

extension View {
    func cardSurface(emphasized: Bool = false) -> some View {
        modifier(CardSurface(emphasized: emphasized))
    }
}

// MARK: - Кнопки

/// Толстая кнопка: заливка и тёмная «губа» снизу. При нажатии кнопка
/// опускается на высоту губы — нажатие видно и чувствуется без анимаций.
struct ChunkyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary

    @Environment(\.isEnabled) private var isEnabled

    /// Явный инициализатор: из-за приватного `isEnabled` поэлементный
    /// был бы недоступен за пределами файла.
    init(kind: Kind = .primary) {
        self.kind = kind
    }

    private var fill: Color {
        switch kind {
        case .primary: return Theme.primary
        case .secondary: return Theme.surface
        case .destructive: return Theme.red
        }
    }

    private var lip: Color {
        switch kind {
        case .primary: return Theme.primaryLip
        case .secondary: return Theme.border
        case .destructive: return Color(red: 0.72, green: 0.18, blue: 0.18)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.onPrimary
        case .secondary: return Theme.ink
        case .destructive: return .white
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .fontWeight(.bold)
            .foregroundStyle(isEnabled ? foreground : Theme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 46)
            .background {
                ZStack {
                    if !pressed {
                        shape.fill(isEnabled ? lip : Theme.border).offset(y: Theme.lip)
                    }
                    shape.fill(isEnabled ? fill : Theme.border.opacity(0.6))
                    if kind == .secondary {
                        shape.strokeBorder(Theme.border, lineWidth: Theme.stroke)
                    }
                }
            }
            .offset(y: pressed ? Theme.lip : 0)
            .padding(.bottom, Theme.lip)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.08), value: pressed)
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { ChunkyButtonStyle(kind: .primary) }
    static var chunkySecondary: ChunkyButtonStyle { ChunkyButtonStyle(kind: .secondary) }
    static var chunkyDestructive: ChunkyButtonStyle { ChunkyButtonStyle(kind: .destructive) }
}

// MARK: - Поля ввода

/// Поле ввода в скруглённой рамке, без губы: губа означает «нажми меня»,
/// а поле нажимать не нужно.
struct SoftTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .panel(fill: Theme.background, lip: false, radius: 14)
    }
}

extension TextFieldStyle where Self == SoftTextFieldStyle {
    static var soft: SoftTextFieldStyle { SoftTextFieldStyle() }
}

// MARK: - Прогресс

/// Толстая полоса прогресса со светлым бликом сверху, как в игровых
/// обучающих приложениях: заполнение видно издалека и одним взглядом.
struct ChunkyProgressBar: View {
    var value: Double
    var total: Double = 1
    var tint: Color = Theme.primary
    var height: CGFloat = 16

    private var fraction: Double {
        guard total > 0, value.isFinite else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                if fraction > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(width, height))
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(0.3))
                                .frame(height: height * 0.28)
                                .padding(.horizontal, height * 0.45)
                                .padding(.top, height * 0.2)
                        }
                }
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded()))%")
    }
}

// MARK: - Значки и строки

/// Значок строки: символ на цветном скруглённом квадрате.
///
/// Голые серые значки делают списки одинаковыми; цветная плашка даёт глазу
/// якорь и различает разделы, не добавляя текста.
struct IconBadge: View {
    let systemName: String
    var color: Color = Theme.primary
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Строка-переход в виде карточки для экранов из карточек, а не списков.
struct CardLink<Destination: View>: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var color: Color = Theme.primary
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                IconBadge(systemName: systemImage, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Заголовок блока на экранах из карточек.
struct CardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.app(.footnote, weight: .heavy))
            .foregroundStyle(Theme.muted)
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
