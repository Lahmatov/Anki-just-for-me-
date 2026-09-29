import Foundation

/// Письмо в поддержку одним нажатием.
///
/// В тело сразу попадают версия приложения, iOS и код поддержки — первое,
/// о чём пришлось бы переспрашивать. Код поддержки нужен и для запросов по
/// GDPR: аккаунтов по почте нет, и найти запись на сервере можно только по нему.
public enum SupportMail {

    public static func looksLikeEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let local = parts.first, let domain = parts.last,
              !local.isEmpty, domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".")
        else { return false }
        return !value.contains(where: { $0.isWhitespace })
    }

    public static func body(appVersion: String, systemVersion: String, supportCode: String?,
                            language: AppLanguage) -> String {
        var lines = ["", "", "—", "Recap \(appVersion) · iOS \(systemVersion) · \(language.rawValue)"]
        if let supportCode { lines.append(tr("Код поддержки: ", "Código de suporte: ", "Support code: ")
                                            + supportCode) }
        return lines.joined(separator: "\n")
    }

    /// Ссылка mailto: с темой и телом. Адрес не заполнен — ссылки нет.
    public static func url(to email: String, subject: String, body: String) -> URL? {
        guard looksLikeEmail(email) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject),
                                 URLQueryItem(name: "body", value: body)]
        // URLComponents не кодирует «+», а почтовые программы читают его как пробел.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
