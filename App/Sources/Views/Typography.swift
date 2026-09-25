import SwiftUI
import UIKit

/// Шрифт интерфейса — на выбор в настройках.
///
/// По умолчанию Manrope: геометричный, с широкими буквами и спокойным ритмом,
/// с кириллицей и всеми португальскими диакритиками. Системный SF хорош, но
/// делает приложение похожим на экран настроек. Остальные варианты —
/// системные, им не нужны файлы.
enum AppFont: String, CaseIterable, Identifiable {
    case manrope
    case system
    case rounded
    case serif

    var id: String { rawValue }

    static var current: AppFont {
        UserDefaults.standard.string(forKey: SettingsKey.fontStyle)
            .flatMap(AppFont.init(rawValue:)) ?? .manrope
    }

    var title: String {
        switch self {
        case .manrope: return "Manrope"
        case .system: return "Системный"
        case .rounded: return "Скруглённый"
        case .serif: return "С засечками"
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

    static func manropeName(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "Manrope-Medium"
        case .semibold: return "Manrope-SemiBold"
        case .bold: return "Manrope-Bold"
        case .heavy, .black: return "Manrope-ExtraBold"
        default: return "Manrope-Regular"
        }
    }

    private var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .manrope, .system: return .default
        }
    }

    func font(_ style: Font.TextStyle, weight: Font.Weight?) -> Font {
        switch self {
        case .manrope:
            return .custom(
                Self.manropeName(weight ?? Self.defaultWeight(style)),
                size: Self.baseSize(style), relativeTo: style)
        case .system, .rounded, .serif:
            return .system(style, design: design, weight: weight)
        }
    }

    // MARK: - UIKit

    /// Заголовки навигации рисует UIKit, и `.font` из SwiftUI до них не
    /// доходит. Без этого заголовок экрана был бы системным, а всё под ним —
    /// нет, и разнобой бросался бы в глаза сильнее любого шрифта.
    func applyToNavigationBars() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: uiFont(size: 34, weight: .bold, style: .largeTitle)]
        bar.titleTextAttributes = [.font: uiFont(size: 17, weight: .semibold, style: .headline)]
    }

    private func uiFont(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base: UIFont
        switch self {
        case .manrope:
            let name = weight == .bold ? "Manrope-Bold" : "Manrope-SemiBold"
            base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
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

    /// Транскрипция всегда системным шрифтом: в Manrope нет части знаков
    /// МФА (ʊ, ɪ, ʌ, ˈ), и транскрипция собиралась бы из двух шрифтов.
    static func ipa(_ style: Font.TextStyle) -> Font {
        .system(style)
    }
}
