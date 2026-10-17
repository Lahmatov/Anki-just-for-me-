import Foundation

/// Страны, где приложение продаётся, но работает без сервера Recap (P-78).
///
/// Россия: 152-ФЗ требует хранить данные граждан РФ в базе на территории
/// России (ст. 18 ч. 5), а сервер Recap — в Cloudflare за рубежом. Без
/// сервера с телефона к нам не уходит ничего: карточки, готовые наборы,
/// повторение, озвучка и распознавание речи работают на телефоне, и
/// оператором данных мы не становимся. Anthropic в России тоже не работает,
/// так что ИИ через сервер там всё равно бы не ответил.
///
/// Страна — магазин App Store (`Storefront.countryCode`, ISO 3166-1 alpha-3),
/// а не язык и не сеть: закон смотрит на то, где сервис распространяется.
public enum RegionPolicy {
    /// Добавить страну — одна строка здесь (Казахстан — "KAZ", Беларусь — "BLR").
    public static let localOnlyStorefronts: Set<String> = ["RUS"]

    /// Можно ли ходить на сервер Recap. Страна неизвестна (StoreKit не
    /// ответил, сборка без магазина) — можно: иначе сбой StoreKit выключал
    /// бы сервер у всех.
    public static func allowsServer(storefront: String?) -> Bool {
        guard let code = storefront?.trimmingCharacters(in: .whitespaces).uppercased(),
              !code.isEmpty else { return true }
        return !localOnlyStorefronts.contains(code)
    }
}
