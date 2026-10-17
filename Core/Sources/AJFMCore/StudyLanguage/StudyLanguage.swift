import Foundation

/// Язык, который учат, — в отличие от `AppLanguage`, языка интерфейса и
/// переводов.
///
/// У каждого изучаемого языка своя жизнь: своя база наборов, своя серия
/// дней, своя карта и подарки Мончика. Переключился — открылась база этого
/// языка; вернулся — всё на месте (P-67). Английский живёт на старых путях
/// и ключах: данные, накопленные до появления языков, никуда не переезжают.
public enum StudyLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    /// Европейский португальский: autocarro, telemóvel, «estar a + infinitivo».
    case portuguese = "pt-PT"
    case italian = "it"

    public var id: String { rawValue }

    /// Английский — язык по умолчанию: приложение начиналось с него.
    public static let `default`: StudyLanguage = .english

    /// Из сохранённого значения; неизвестное и пустое — английский, чтобы
    /// испорченная настройка не оставляла человека без его наборов.
    public static func stored(_ raw: String?) -> StudyLanguage {
        raw.flatMap(StudyLanguage.init(rawValue:)) ?? .default
    }

    // MARK: - Речь

    /// Голос озвучки и распознавание речи.
    public var speechLocale: String {
        switch self {
        case .english: return "en-US"
        case .portuguese: return "pt-PT"
        case .italian: return "it-IT"
        }
    }

    // MARK: - Хранение

    /// Имя файла базы. У английского — `nil`: он остаётся в базе по
    /// умолчанию, где лежит всё, что накоплено до появления языков.
    public var storeName: String? {
        switch self {
        case .english: return nil
        case .portuguese: return "Recap-pt-PT"
        case .italian: return "Recap-it"
        }
    }

    /// Ключ настройки, принадлежащей этому языку: серия, карта, уровень.
    /// Английский — без приставки, чтобы прежние значения продолжали работать.
    public func scopedKey(_ key: String) -> String {
        self == .english ? key : "\(rawValue).\(key)"
    }

    /// Приставка в именах файлов резервных копий; у английского пустая —
    /// старые копии остаются английскими.
    public var backupPrefix: String {
        self == .english ? "" : "\(rawValue)-"
    }

    // MARK: - Подписи

    /// Название на самом языке — как в переключателе.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .portuguese: return "Português"
        case .italian: return "Italiano"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .portuguese: return "🇵🇹"
        case .italian: return "🇮🇹"
        }
    }

    /// Название для модели — с вариантом, чтобы она не смешивала нормы.
    public var promptName: String {
        switch self {
        case .english: return "American English"
        case .portuguese: return "European Portuguese (as spoken in Portugal, never Brazilian)"
        case .italian: return "standard Italian"
        }
    }

    /// Какая транскрипция в карточках.
    public var ipaStyle: String {
        switch self {
        case .english: return "General American transcription"
        case .portuguese: return "European Portuguese (Lisbon) transcription"
        case .italian: return "standard Italian transcription"
        }
    }

    /// На каком языке переводы в карточках. Обычно — язык интерфейса; но
    /// учить португальский с переводом на португальский бессмысленно, тогда
    /// переводим на английский. Английский с английским интерфейсом остаётся
    /// как был — с толкованиями.
    public func translationLanguage(for interface: AppLanguage) -> AppLanguage {
        if self == .portuguese && interface == .portuguese { return .english }
        return interface
    }

    /// Каталог сериалов, тест уровня и карта по сериям сделаны для
    /// английского: слова к американским сериалам и вопросы на английском.
    public var hasShowCatalog: Bool { self == .english }
    public var hasPlacementTest: Bool { self == .english }
}

/// Имена файлов еженедельных бэкапов: у каждого языка свои, и старые
/// английские («ajfm-2026-09-30-1200.json») остаются английскими.
public enum BackupFileName {
    public static func make(stamp: String, language: StudyLanguage) -> String {
        "ajfm-\(language.backupPrefix)\(stamp).json"
    }

    /// Принадлежит ли файл языку — чтобы чистка старых копий одного языка
    /// не удаляла копии другого.
    public static func belongs(_ name: String, to language: StudyLanguage) -> Bool {
        guard name.hasPrefix("ajfm-"), name.hasSuffix(".json") else { return false }
        let rest = name.dropFirst("ajfm-".count)
        if language == .english {
            // Английские — сразу с даты: «ajfm-2026-…».
            return rest.first?.isNumber == true
        }
        return rest.hasPrefix(language.backupPrefix)
    }
}
