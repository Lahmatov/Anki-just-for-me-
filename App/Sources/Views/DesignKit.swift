import SwiftUI
import UIKit

/// Общие примитивы оформления — пиксельный ретро-стиль в духе RetroUI
/// (github.com/Dksie09/RetroUI): толстые чёрные рамки со ступенчатыми
/// углами, жёсткие тени без размытия, кнопки, которые «вдавливаются»,
/// кремовый фон и фиолетовый акцент. Подробности — docs/design.md.
///
/// Правила, которым подчиняется всё остальное:
/// 1. Цвет означает смысл (верно, ошибка, зрелость), а не украшает.
/// 2. На экране одно очевидное действие; всё прочее — тише и мельче.
/// 3. Учат обычно одной рукой и на ходу, поэтому главные кнопки крупные и внизу.
enum Design {
    static let cardPadding: CGFloat = 18
    static let stackSpacing: CGFloat = 18

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

/// Цвета ретро-темы. Живут в каталоге ассетов: у каждого светлый и тёмный
/// вариант, контраст проверен расчётом (docs/design.md).
enum Retro {
    static let background = Color("RetroBackground")
    static let surface = Color("RetroSurface")
    static let ink = Color("RetroInk")
    static let muted = Color("RetroMuted")
    static let shadow = Color("RetroShadow")
    static let cardShadow = Color("RetroCardShadow")
    static let primary = Color("RetroPrimary")
    static let onPrimary = Color("RetroOnPrimary")
    static let secondary = Color("RetroSecondary")

    /// Размер «пикселя»: толщина рамки и ступенька угла.
    static let pixel: CGFloat = 3
    /// Сдвиг жёсткой тени.
    static let shadowOffset: CGFloat = 4
}

/// Прямоугольник со ступенчатыми углами — как рамка в пиксельной графике.
struct PixelRect: Shape {
    var step: CGFloat = Retro.pixel

    func path(in rect: CGRect) -> Path {
        let s = min(step, rect.width / 2, rect.height / 2)
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        var path = Path()
        path.move(to: CGPoint(x: minX + s, y: minY))
        path.addLine(to: CGPoint(x: maxX - s, y: minY))
        path.addLine(to: CGPoint(x: maxX - s, y: minY + s))
        path.addLine(to: CGPoint(x: maxX, y: minY + s))
        path.addLine(to: CGPoint(x: maxX, y: maxY - s))
        path.addLine(to: CGPoint(x: maxX - s, y: maxY - s))
        path.addLine(to: CGPoint(x: maxX - s, y: maxY))
        path.addLine(to: CGPoint(x: minX + s, y: maxY))
        path.addLine(to: CGPoint(x: minX + s, y: maxY - s))
        path.addLine(to: CGPoint(x: minX, y: maxY - s))
        path.addLine(to: CGPoint(x: minX, y: minY + s))
        path.addLine(to: CGPoint(x: minX + s, y: minY + s))
        path.closeSubpath()
        return path
    }
}

/// Пиксельная рамка с жёсткой тенью. Рисуется заливками, а не обводкой:
/// обводка ступенчатого контура на углах даёт «лесенку» разной толщины,
/// а внутренняя фигура, сдвинутая на пиксель, — ровную рамку.
struct PixelFrame: ViewModifier {
    var fill: Color = Retro.surface
    var border: Color = Retro.ink
    var shadow: Color? = Retro.cardShadow
    var pixel: CGFloat = Retro.pixel

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if let shadow {
                    PixelRect(step: pixel)
                        .fill(shadow)
                        .offset(x: Retro.shadowOffset, y: Retro.shadowOffset)
                }
                PixelRect(step: pixel).fill(border)
                PixelRect(step: pixel).fill(fill).padding(pixel)
            }
        }
    }
}

extension View {
    func pixelFrame(
        fill: Color = Retro.surface, border: Color = Retro.ink,
        shadow: Color? = Retro.cardShadow, pixel: CGFloat = Retro.pixel
    ) -> some View {
        modifier(PixelFrame(fill: fill, border: border, shadow: shadow, pixel: pixel))
    }

    /// Фон экрана со списком или формой: кремовый вместо системного серого.
    func retroScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Retro.background.ignoresSafeArea())
    }
}

/// Поверхность карточки — пиксельная рамка с тенью. Выделенная карточка
/// (ответ открыт) получает тень акцентного цвета.
struct CardSurface: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelFrame(shadow: emphasized ? Retro.primary : Retro.cardShadow)
            // Тень выступает за рамку — место под неё, чтобы соседи не наезжали.
            .padding(.trailing, Retro.shadowOffset)
            .padding(.bottom, Retro.shadowOffset)
    }
}

extension View {
    func cardSurface(emphasized: Bool = false) -> some View {
        modifier(CardSurface(emphasized: emphasized))
    }
}

// MARK: - Кнопки

/// Кнопка RetroUI: пиксельная рамка, жёсткая тень, при нажатии кнопка
/// «вдавливается» на место тени. Нажатие видно без анимаций и стекла.
struct RetroButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary

    @Environment(\.isEnabled) private var isEnabled

    private var fill: Color {
        switch kind {
        case .primary: return Retro.primary
        case .secondary: return Retro.secondary
        case .destructive: return Color(red: 0.93, green: 0.36, blue: 0.33)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Retro.onPrimary
        case .secondary: return Retro.ink
        case .destructive: return .black
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background {
                ZStack {
                    if !pressed {
                        PixelRect()
                            .fill(Retro.shadow)
                            .offset(x: Retro.shadowOffset, y: Retro.shadowOffset)
                    }
                    PixelRect().fill(Retro.ink)
                    PixelRect().fill(fill).padding(Retro.pixel)
                }
            }
            .offset(x: pressed ? Retro.shadowOffset : 0, y: pressed ? Retro.shadowOffset : 0)
            .padding(.trailing, Retro.shadowOffset)
            .padding(.bottom, Retro.shadowOffset)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == RetroButtonStyle {
    static var retro: RetroButtonStyle { RetroButtonStyle(kind: .primary) }
    static var retroSecondary: RetroButtonStyle { RetroButtonStyle(kind: .secondary) }
    static var retroDestructive: RetroButtonStyle { RetroButtonStyle(kind: .destructive) }
}

// MARK: - Поля ввода

/// Поле ввода в пиксельной рамке, без тени: тень у кнопок означает
/// «нажми меня», а поле нажимать не нужно.
struct RetroTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .pixelFrame(shadow: nil)
    }
}

extension TextFieldStyle where Self == RetroTextFieldStyle {
    static var retro: RetroTextFieldStyle { RetroTextFieldStyle() }
}

// MARK: - Прогресс

/// Полоса прогресса из отдельных блоков, как индикатор загрузки в старых
/// играх. Заполняется целыми блоками — плавная полоса выбивалась бы из стиля.
struct RetroProgressBar: View {
    var value: Double
    var total: Double = 1
    var tint: Color = Retro.primary
    var height: CGFloat = 20

    private var fraction: Double {
        guard total > 0, value.isFinite else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let block: CGFloat = 8
            let gap: CGFloat = 2
            let inner = max(0, geometry.size.width - 2 * Retro.pixel - 6)
            let capacity = Int((inner + gap) / (block + gap))
            let filled = Int((Double(capacity) * fraction).rounded(.down))
            HStack(spacing: gap) {
                ForEach(0..<max(filled, 0), id: \.self) { _ in
                    Rectangle().fill(tint).frame(width: block)
                }
            }
            .padding(Retro.pixel + 3)
            .frame(width: geometry.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .pixelFrame(shadow: nil)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded()))%")
    }
}

// MARK: - Значки и строки

/// Значок строки: символ на цветном пиксельном квадрате.
///
/// Голые серые значки делают списки одинаковыми; цветная плашка даёт глазу
/// якорь и различает разделы, не добавляя текста.
struct IconBadge: View {
    let systemName: String
    var color: Color = Retro.primary
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    PixelRect(step: 2).fill(Retro.ink)
                    PixelRect(step: 2).fill(color).padding(2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Строка-переход в виде карточки для экранов из карточек, а не списков.
struct CardLink<Destination: View>: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var color: Color = Retro.primary
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                IconBadge(systemName: systemImage, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(Retro.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(Retro.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Retro.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelFrame()
            .padding(.trailing, Retro.shadowOffset)
            .padding(.bottom, Retro.shadowOffset)
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
            .font(.app(.footnote, weight: .bold))
            .foregroundStyle(Retro.muted)
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
