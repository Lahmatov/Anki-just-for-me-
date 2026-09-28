import SwiftUI
import UIKit
import AJFMCore

/// Шрифт интерфейса — на выбор в настройках.
///
/// По умолчанию — Nunito: скруглённый, с открытыми формами и крупным
/// очком, его легко читать на ходу — поэтому такие шрифты и стоят в
/// большинстве обучающих приложений. Пиксельные шрифты ретро-темы
/// оказались на телефоне нечитаемыми и удалены. У Nunito и Rubik есть
/// кириллица и все португальские диакритики.
enum AppFont: String, CaseIterable, Identifiable {
    case nunito
    case rubik
    case system
    case rounded
    case serif

    var id: String { rawValue }

    /// Сохранённые значения удалённых шрифтов (pixel, manrope) не находятся
    /// среди вариантов и тихо превращаются в шрифт по умолчанию.
    static var current: AppFont {
        UserDefaults.standard.string(forKey: SettingsKey.fontStyle)
            .flatMap(AppFont.init(rawValue:)) ?? .nunito
    }

    var title: String {
        switch self {
        case .nunito: return "Nunito"
        case .rubik: return "Rubik"
        case .system: return tr("Системный", "Do sistema", "System")
        case .rounded: return tr("Системный скруглённый", "Arredondado do sistema",
                                 "System rounded")
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

    /// Жирность по умолчанию. Заголовки у Nunito жирнее системных:
    /// тонкий скруглённый шрифт в крупном кегле выглядит блёкло.
    static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .largeTitle, .title: return .heavy
        case .title2, .title3, .headline: return .bold
        default: return .regular
        }
    }

    /// Имя начертания в бандле. Недостающие веса сводятся к ближайшим:
    /// у Nunito нет Medium, у Rubik — ExtraBold и Black.
    func customName(_ weight: Font.Weight) -> String? {
        switch self {
        case .nunito:
            switch weight {
            case .medium, .semibold: return "Nunito-SemiBold"
            case .bold: return "Nunito-Bold"
            case .heavy: return "Nunito-ExtraBold"
            case .black: return "Nunito-Black"
            default: return "Nunito-Regular"
            }
        case .rubik:
            switch weight {
            case .medium: return "Rubik-Medium"
            case .semibold: return "Rubik-SemiBold"
            case .bold, .heavy, .black: return "Rubik-Bold"
            default: return "Rubik-Regular"
            }
        case .system, .rounded, .serif:
            return nil
        }
    }

    private var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .nunito, .rubik, .system: return .default
        }
    }

    func font(_ style: Font.TextStyle, weight: Font.Weight?) -> Font {
        let weight = weight ?? Self.defaultWeight(style)
        if let name = customName(weight) {
            return .custom(name, size: Self.baseSize(style), relativeTo: style)
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
            .foregroundColor: UIColor(named: "ThemeInk") ?? .label,
        ]
        bar.titleTextAttributes = [
            .font: uiFont(size: 17, weight: .semibold, style: .headline),
            .foregroundColor: UIColor(named: "ThemeInk") ?? .label,
        ]
    }

    private func uiFont(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base: UIFont
        switch self {
        case .nunito, .rubik:
            let name = customName(weight == .bold ? .heavy : .bold) ?? ""
            base = UIFont(name: name, size: size)
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

    /// Крупные цифры — счётчики, уровень, точность: самый тяжёлый вес,
    /// как на табло в играх.
    static func display(_ style: Font.TextStyle) -> Font {
        .app(style, weight: .black)
    }

    /// Транскрипция всегда системным шрифтом: ни в Nunito, ни в Rubik
    /// нет части знаков МФА (ʊ, ɪ, ʌ, ˈ), и транскрипция собиралась бы
    /// из двух шрифтов.
    static func ipa(_ style: Font.TextStyle) -> Font {
        .system(style)
    }
}
