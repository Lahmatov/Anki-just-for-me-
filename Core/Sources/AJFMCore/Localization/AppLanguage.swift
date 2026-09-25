import Foundation

/// Язык интерфейса и он же — родной язык ученика: на нём переводы в
/// карточках, объяснения ошибок и разборы пересказов.
///
/// Одна настройка вместо двух намеренно: человек, выбравший португальский
/// интерфейс, почти наверняка хочет и переводы на португальский, а две
/// рассогласованные настройки — источник странных наборов.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case russian = "ru"
    case portuguese = "pt"
    case english = "en"

    /// Язык по списку предпочтений системы: первый, который приложение знает.
    /// Если не знает ни одного — английский: он понятен чаще, чем русский.
    public static func resolve(preferred: [String]) -> AppLanguage {
        for identifier in preferred {
            let code = identifier.lowercased()
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first.map(String.init) ?? ""
            if let language = AppLanguage(rawValue: code) { return language }
        }
        return .english
    }

    /// Название на самом языке — так его ищут глазами в списке.
    public var nativeName: String {
        switch self {
        case .russian: return "Русский"
        case .portuguese: return "Português"
        case .english: return "English"
        }
    }

    /// Как назвать язык в запросе к модели.
    ///
    /// Португальский — европейский: бразильский вариант заметно расходится
    /// в лексике (ônibus / autocarro), и перевод «вообще на португальский»
    /// получался бы то одним, то другим.
    public var promptName: String {
        switch self {
        case .russian: return "Russian"
        case .portuguese: return "European Portuguese (as spoken in Portugal)"
        case .english: return "English"
        }
    }

    /// Для английского интерфейса «перевод» — это короткое толкование
    /// простыми словами, как в учебном словаре.
    public var translatesIntoItself: Bool { self == .english }
}
