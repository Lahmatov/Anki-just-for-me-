import SwiftUI
import UIKit
import AJFMCore

/// Шрифт интерфейса — на выбор в настройках.
///
/// По умолчанию — «ретро»: пиксельный Pixelify Sans в заголовках, кнопках
/// и словах на карточках, а весь остальной текст — Rubik. Пиксельный шрифт
/// хорош крупно, но абзац пояснения им читать тяжело, поэтому мелкий текст
/// набран обычным гротеском с мягкими формами, который не спорит с пикселями.
/// У обоих есть кириллица и все португальские диакритики. Остальные
/// варианты — для тех, кому пиксели надоедят: Manrope и системные.
enum AppFont: String, CaseIterable, Identifiable {
    case pixel
    case manrope
    case system
    case rounded
    case serif

    var id: String { rawValue }

    static var current: AppFont {
        UserDefaults.standard.string(forKey: SettingsKey.fontStyle)
            .flatMap(AppFont.init(rawValue:)) ?? .pixel
    }

    var title: String {
        switch self {
        case .pixel: return tr("Ретро", "Retro", "Retro")
        case .manrope: return "Manrope"
        case .system: return tr("Системный", "Do sistema", "System")
        case .rounded: return tr("Скруглённый", "Arredondado", "Rounded")
        case .serif: return tr("С засечками", "Com serifa", "Serif")
        }
    }

    /// Размеры текстовых стилей при стандартном размере текста.
    /// Дальше их масштабирует Dynamic Type через `relativeTo:`.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }

    /// Жирность по умолчанию — как у системных стилей.
    static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }

    /// Стили, которые в ретро-теме набираются пиксельным шрифтом: крупные
    /// и короткие. Всё мельче `headline` — читаемым Rubik.
    static func isPixelStyle(_ style: Font.TextStyle) -> Bool {
        switch style {
        case .largeTitle, .title, .title2, .title3, .headline: return true
        default: return false
        }
    }

    /// Имя начертания в бандле. У Pixelify Sans и Rubik в бандле нет
    /// ExtraBold — тяжёлые веса сводятся к Bold.
    func customName(_ weight: Font.Weight, style: Font.TextStyle = .headline) -> String? {
        let family: String
        switch self {
        case .pixel: family = Self.isPixelStyle(style) ? "PixelifySans" : "Rubik"
        case .manrope: family = "Manrope"
        case .system, .rounded, .serif: return nil
        }
        switch weight {
        case .medium: return "\(family)-Medium"
        case .semibold: return "\(family)-SemiBold"
        case .bold: return "\(family)-Bold"
        case .heavy, .black: return self == .manrope ? "Manrope-ExtraBold" : "\(family)-Bold"
        default: return "\(family)-Regular"
        }
    }

    /// Пиксельный шрифт при той же высоте кажется мельче гротеска —
    /// заголовки чуть крупнее.
    private func scale(_ style: Font.TextStyle) -> CGFloat {
        self == .pixel && Self.isPixelStyle(style) ? 1.08 : 1
    }

    private var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .pixel, .manrope, .system: return .default
        }
    }

    func font(_ style: Font.TextStyle, weight: Font.Weight?) -> Font {
        if let name = customName(weight ?? Self.defaultWeight(style), style: style) {
            return .custom(name, size: Self.baseSize(style) * scale(style), relativeTo: style)
        }
        return .system(style, design: design, weight: weight)
    }

    // MARK: - UIKit

    /// Заголовки навигации рисует UIKit, и `.font` из SwiftUI до них не
    /// доходит. Без этого заголовок экрана был бы системным, а всё под ним —
    /// нет, и разнобой бросался бы в глаза сильнее любого шрифта.
    func applyToNavigationBars() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: uiFont(size: 32, weight: .bold, style: .largeTitle),
            .foregroundColor: UIColor(named: "RetroInk") ?? .label,
        ]
        bar.titleTextAttributes = [
            .font: uiFont(size: 17, weight: .semibold, style: .headline),
            .foregroundColor: UIColor(named: "RetroInk") ?? .label,
        ]
    }

    private func uiFont(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base: UIFont
        switch self {
        case .pixel, .manrope:
            let name = customName(weight == .bold ? .bold : .semibold) ?? ""
            base = UIFont(name: name, size: size * scale(.headline))
                ?? .systemFont(ofSize: size, weight: weight)
        case .system, .rounded, .serif:
            let system = UIFont.systemFont(ofSize: size, weight: weight)
            let uiDesign: UIFontDescriptor.SystemDesign =
                self == .rounded ? .rounded : self == .serif ? .serif : .default
            base = system.fontDescriptor.withDesign(uiDesign)
                .map { UIFont(descriptor: $0, size: size) } ?? system
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

extension Font {
    /// Шрифт интерфейса для текстового стиля. Все тексты приложения
    /// идут через него — иначе смена шрифта в настройках задевала бы
    /// только часть экранов.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        AppFont.current.font(style, weight: weight)
    }

    /// Крупные цифры — счётчики, уровень, точность. В пиксельной теме это
    /// Press Start 2P: цифры как на табло старой приставки.
    static func display(_ style: Font.TextStyle) -> Font {
        guard AppFont.current == .pixel else { return .app(style, weight: .heavy) }
        // Press Start 2P очень широкий: при системном кегле цифры вылезают
        // за карточку, поэтому базовый размер вдвое меньше.
        return .custom("PressStart2P-Regular", size: AppFont.baseSize(style) * 0.62,
                       relativeTo: style)
    }

    /// Транскрипция всегда системным шрифтом: ни в Manrope, ни в Pixelify
    /// нет части знаков МФА (ʊ, ɪ, ʌ, ˈ), и транскрипция собиралась бы
    /// из двух шрифтов.
    static func ipa(_ style: Font.TextStyle) -> Font {
        .system(style)
    }
}
