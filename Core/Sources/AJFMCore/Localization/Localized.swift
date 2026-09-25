import Foundation

/// Текущий язык интерфейса.
///
/// Своя маленькая локализация вместо String Catalog — осознанно (решение
/// P-28 в docs/decisions.md). Каждая строка записывается сразу на трёх
/// языках вызовом `tr(ru, pt, en)`: пропустить перевод не даст компилятор,
/// а язык переключается в настройках мгновенно, без перезапуска —
/// системная локализация выбирает язык один раз при старте процесса.
public enum Loc {
    /// Меняется из настроек и знакомства; экраны после этого перестраиваются.
    public static var language: AppLanguage = .russian
}

/// Строка на текущем языке.
public func tr(_ ru: String, _ pt: String, _ en: String) -> String {
    switch Loc.language {
    case .russian: return ru
    case .portuguese: return pt
    case .english: return en
    }
}

/// Форма слова при числе — по правилам текущего языка.
///
/// Русский: одна, две–четыре, пять (1 день, 2 дня, 5 дней).
/// Португальский (европейский) и английский: единственное только для 1 —
/// «0 palavras», «0 words».
public func trForm(
    _ count: Int,
    ru: (one: String, few: String, many: String),
    pt: (one: String, other: String),
    en: (one: String, other: String)
) -> String {
    switch Loc.language {
    case .russian:
        return RussianPlural.form(count, one: ru.one, few: ru.few, many: ru.many)
    case .portuguese:
        return count == 1 ? pt.one : pt.other
    case .english:
        return count == 1 ? en.one : en.other
    }
}

/// Число вместе со словом: «3 дня», «3 dias», «3 days».
public func trCount(
    _ count: Int,
    ru: (one: String, few: String, many: String),
    pt: (one: String, other: String),
    en: (one: String, other: String)
) -> String {
    "\(count) " + trForm(count, ru: ru, pt: pt, en: en)
}

/// Счётные слова, которые встречаются по всему приложению.
public enum Counted {
    public static func words(_ count: Int) -> String {
        trCount(count, ru: ("слово", "слова", "слов"),
                pt: ("palavra", "palavras"), en: ("word", "words"))
    }

    public static func days(_ count: Int) -> String {
        trCount(count, ru: ("день", "дня", "дней"),
                pt: ("dia", "dias"), en: ("day", "days"))
    }

    public static func cards(_ count: Int) -> String {
        trCount(count, ru: ("карточка", "карточки", "карточек"),
                pt: ("cartão", "cartões"), en: ("card", "cards"))
    }

    /// Винительный падеж для русского: «учить 1 карточку».
    /// В португальском и английском падежей нет — формы те же.
    public static func cardsAccusative(_ count: Int) -> String {
        trCount(count, ru: ("карточку", "карточки", "карточек"),
                pt: ("cartão", "cartões"), en: ("card", "cards"))
    }

    public static func times(_ count: Int) -> String {
        trCount(count, ru: ("раз", "раза", "раз"),
                pt: ("vez", "vezes"), en: ("time", "times"))
    }

    public static func decks(_ count: Int) -> String {
        trCount(count, ru: ("набор", "набора", "наборов"),
                pt: ("baralho", "baralhos"), en: ("deck", "decks"))
    }

    public static func minutes(_ count: Int) -> String {
        trCount(count, ru: ("минута", "минуты", "минут"),
                pt: ("minuto", "minutos"), en: ("minute", "minutes"))
    }
}
