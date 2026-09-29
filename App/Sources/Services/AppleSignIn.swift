import Foundation
import AuthenticationServices
import CryptoKit
import Security
import AJFMCore

/// Вход через Apple — единственный способ входа.
///
/// Почему только Apple: паролей хранить не нужно, чужих SDK нет, а раз
/// приложение для iPhone, Apple ID есть у каждого. Добавь мы Google — по
/// правилу 4.8 всё равно пришлось бы предлагать и Apple.
///
/// Способность Sign in with Apple требует платного аккаунта разработчика.
/// На бесплатном её нет, и сборка с ней не подпишется, поэтому она
/// включается флагом в `Config/Signing.xcconfig` (см. там же).
enum AppleSignIn {

    /// Включена ли способность в этой сборке (`RecapSignInWithApple` в Info.plist).
    static var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "RecapSignInWithApple") as? String)?
            .uppercased() == "YES"
    }

    /// Одноразовая строка: её SHA-256 уходит в запрос к Apple и оказывается
    /// внутри токена, а сама строка — на сервер. Перехваченный токен без
    /// неё бесполезен.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Системный генератор не отказывает на практике; но и без него
            // nonce должен быть непредсказуемым.
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Что отправить на сервер из ответа Apple. Имя приходит только при
    /// первом входе — его забирает профиль.
    struct Result {
        var body: BackendAPI.SignInBody
        var givenName: String?
        var familyName: String?
    }

    enum Failure: LocalizedError {
        case cancelled
        case notAvailable
        case incomplete

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil
            case .notAvailable:
                return tr("Вход через Apple работает в сборке с платным аккаунтом разработчика.",
                          "O início de sessão com a Apple funciona na versão com conta de programador paga.",
                          "Sign in with Apple works in builds with a paid developer account.")
            case .incomplete:
                return tr("Apple не прислал данные входа. Попробуй ещё раз.",
                          "A Apple não enviou os dados de início de sessão. Tenta outra vez.",
                          "Apple didn't send the sign-in data. Try again.")
            }
        }
    }

    static func result(from authorization: ASAuthorization, nonce: String) throws -> Result {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
              let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) })
        else { throw Failure.incomplete }
        return Result(
            body: BackendAPI.SignInBody(identityToken: token, authorizationCode: code, nonce: nonce),
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName)
    }

    /// Ошибка системного окна входа — человеку понятными словами.
    static func failure(from error: Error) -> Failure {
        guard let authError = error as? ASAuthorizationError else { return .incomplete }
        switch authError.code {
        case .canceled: return .cancelled
        // «unknown» (1000) — так выглядит сборка без способности Sign in with Apple.
        case .unknown, .notHandled: return .notAvailable
        default: return .incomplete
        }
    }
}
