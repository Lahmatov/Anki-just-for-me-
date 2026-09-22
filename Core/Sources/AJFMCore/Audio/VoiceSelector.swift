import Foundation

public enum VoiceQuality: Int, Comparable, Sendable, CaseIterable {
    case compact = 1
    case enhanced = 2
    case premium = 3

    public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .compact: return "базовое"
        case .enhanced: return "улучшенное"
        case .premium: return "высшее"
        }
    }
}

/// Описание системного голоса, независимое от AVFoundation — чтобы выбор
/// голоса можно было проверить тестами без устройства.
public struct VoiceDescriptor: Equatable, Sendable {
    public var identifier: String
    public var language: String
    public var quality: VoiceQuality
    public var name: String

    public init(identifier: String, language: String, quality: VoiceQuality, name: String) {
        self.identifier = identifier
        self.language = language
        self.quality = quality
        self.name = name
    }
}

/// Выбор голоса для озвучки.
///
/// Подводный камень, ради которого это вынесено отдельно: система по умолчанию
/// подсовывает голос качества compact, и слово звучит роботом. Улучшенные голоса
/// надо скачать в настройках iOS, а в коде — выбрать явно, иначе система
/// молча возьмёт сжатый. См. docs/research.md, раздел про озвучку.
public enum VoiceSelector {

    /// Лучший доступный голос для языка: сначала premium, затем enhanced,
    /// и только в последнюю очередь compact.
    public static func best(
        from voices: [VoiceDescriptor], language: String
    ) -> VoiceDescriptor? {
        let matching = voices.filter { matches($0.language, language) }
        guard !matching.isEmpty else { return nil }

        // При равном качестве берём первый по идентификатору — чтобы голос
        // не прыгал между запусками приложения.
        return matching.sorted {
            $0.quality == $1.quality
                ? $0.identifier < $1.identifier
                : $0.quality > $1.quality
        }.first
    }

    /// Стоит ли предложить скачать голос получше.
    public static func shouldSuggestBetterVoice(
        from voices: [VoiceDescriptor], language: String
    ) -> Bool {
        guard let best = best(from: voices, language: language) else { return false }
        return best.quality == .compact
    }

    public static let downloadHint =
        "Голос звучит роботом? Настройки → Универсальный доступ → Устный контент → "
        + "Голоса → English (US): скачай голос с пометкой «Улучшенный» или «Премиум»."

    /// `en-US` совпадает с `en-US`, но не с `en-GB`. Сравнение регистронезависимое,
    /// а дефис и подчёркивание считаются одним и тем же разделителем.
    static func matches(_ voiceLanguage: String, _ requested: String) -> Bool {
        normalized(voiceLanguage) == normalized(requested)
    }

    private static func normalized(_ language: String) -> String {
        language.lowercased().replacingOccurrences(of: "_", with: "-")
    }
}

/// Скорость озвучки. Отдельный тип, потому что «помедленнее» — основная кнопка
/// в карточке на аудирование: с первого раза беглую речь не разобрать.
public enum SpeechRate: String, CaseIterable, Sendable {
    case slow, normal

    public var title: String {
        switch self {
        case .slow: return "Медленно"
        case .normal: return "Обычно"
        }
    }

    /// Множитель к системной скорости по умолчанию.
    public var multiplier: Float {
        switch self {
        case .slow: return 0.6
        case .normal: return 1.0
        }
    }
}
