import Foundation
import StoreKit
import AJFMCore

/// Страна магазина App Store (P-78): от неё зависит, ходит ли приложение
/// на сервер Recap. Запоминается, чтобы решение было известно сразу при
/// запуске, до ответа StoreKit.
enum RegionService {
    static let key = "storefrontCountry"

    static var storefront: String? { UserDefaults.standard.string(forKey: key) }
    static var allowsServer: Bool { RegionPolicy.allowsServer(storefront: storefront) }

    /// Первым делом при запуске — раньше любого обращения к серверу.
    static func refresh() async {
        guard let code = await Storefront.current?.countryCode else { return }
        if code != storefront {
            UserDefaults.standard.set(code, forKey: key)
            Log.info(.app, "Магазин App Store", detail: code)
        }
    }
}
