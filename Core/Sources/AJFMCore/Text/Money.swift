import Foundation

/// Суммы в долларах (цены API Anthropic): по правилам языка интерфейса,
/// а не `String(format: "$%.2f")` — в португальском «0,01 US$», а не «$0.01».
public enum Money {
    public static func usd(_ amount: Double, fractionDigits: Int = 2,
                           locale: Locale = Locale(identifier: Loc.language.localeIdentifier)) -> String {
        amount.formatted(.currency(code: "USD")
            .precision(.fractionLength(fractionDigits))
            .locale(locale))
    }
}
