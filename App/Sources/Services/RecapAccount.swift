import Foundation
import StoreKit
import Observation
import AJFMCore

/// Доступ к Recap Plus: подписка через App Store и промокоды.
///
/// Покупку проверяет не приложение, а сервер — у Apple, по номеру
/// транзакции. Приложение только передаёт номер и показывает ответ:
/// подменить «я подписан» на телефоне бессмысленно, сервер не поверит.
@Observable
@MainActor
final class RecapAccount {
    static let shared = RecapAccount()

    /// Товары подписки в App Store Connect. Те же — в SUBSCRIPTION_PRODUCTS сервера.
    static let productIDs = ["com.lahmatov.ajfm.plus.monthly", "com.lahmatov.ajfm.plus.yearly"]

    private(set) var plan: BackendAPI.PlanStatus?
    /// Вход через Apple на сервере. Правда — у сервера: приходит с /v1/me.
    private(set) var signedIn = false
    /// Код поддержки этого телефона на сервере — для письма в поддержку.
    private(set) var supportCode: String?
    /// Свои промокоды RECAP-… — только вне App Store (TestFlight, Xcode).
    /// Правило App Store 3.1.1 запрещает открывать функции своими кодами;
    /// в магазинной версии для этого есть Offer Codes от Apple.
    private(set) var ownPromoCodesAllowed = false
    private(set) var products: [Product] = []
    private(set) var busy = false
    var message: String?

    private var updates: Task<Void, Never>?

    /// Запросы к ИИ идут через сервер, когда он подключён и доступ активен.
    var usesBackend: Bool { RecapBackend.isConfigured && plan?.active == true }

    var isAvailable: Bool { RecapBackend.isConfigured }

    // MARK: - Запуск

    /// При старте приложения: слушать покупки, обновить статус, свериться
    /// с App Store — подписка могла продлиться, пока приложение спало.
    func start() {
        guard RecapBackend.isConfigured, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.register(transaction)
                await transaction.finish()
            }
        }
        Task {
            await detectEnvironment()
            await refresh()
            await syncEntitlements()
        }
    }

    func refresh() async {
        guard RecapBackend.isConfigured else { return }
        do {
            update(try await RecapBackend.shared.plan())
        } catch {
            Log.warning(.network, "Статус Recap Plus не обновился", detail: error.localizedDescription)
        }
    }

    /// Ответ сервера после запроса к ИИ несёт свежий остаток — без лишнего запроса.
    /// Признака входа в таких ответах нет, и прежний не затирается.
    func update(_ plan: BackendAPI.PlanStatus) {
        self.plan = plan
        if let signedIn = plan.signedIn { self.signedIn = signedIn }
        if let supportCode = plan.supportCode { self.supportCode = supportCode }
    }

    // MARK: - Вход через Apple

    /// Вход: сервер проверяет токен у Apple, и доступ аккаунта (подписка
    /// или промокод с другого телефона) появляется здесь.
    func signIn(_ result: AppleSignIn.Result) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            update(try await RecapBackend.shared.signIn(result.body))
            ProfileStore.shared.adoptName(givenName: result.givenName, familyName: result.familyName)
            Log.info(.app, "Вход через Apple выполнен")
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Выход забирает с телефона доступ аккаунта. Подписка, купленная
    /// с Apple ID этого телефона, возвращается сразу — сверкой с App Store.
    func signOut() async {
        busy = true
        defer { busy = false }
        do {
            update(try await RecapBackend.shared.signOut())
            Log.info(.app, "Выход из аккаунта")
        } catch {
            message = error.localizedDescription
            return
        }
        await syncEntitlements()
    }

    /// Удалить аккаунт (правило App Store 5.1.1(v)). Слова и прогресс на
    /// телефоне не трогаются — для них есть «Удалить все данные».
    func deleteAccount() async -> Bool {
        busy = true
        defer { busy = false }
        do {
            update(try await RecapBackend.shared.deleteAccount())
            Log.info(.app, "Аккаунт удалён")
        } catch {
            message = error.localizedDescription
            return false
        }
        await syncEntitlements()
        return true
    }

    /// Часть «Удалить все данные»: если вход выполнен — сначала аккаунт.
    func deleteAccountIfSignedIn() async throws {
        guard RecapBackend.isConfigured, signedIn else { return }
        do {
            update(try await RecapBackend.shared.deleteAccount())
        } catch let failure as BackendAPI.Failure where failure.code == "not_signed_in" {
            signedIn = false
        }
    }

    /// После «Удалить все данные» телефон — как новый.
    func forgetLocalState() {
        plan = nil
        signedIn = false
        supportCode = nil
    }

    // MARK: - Покупка

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
        } catch {
            Log.failure(.network, "Товары App Store не загрузились", error)
        }
    }

    func purchase(_ product: Product) async {
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = tr("App Store не подтвердил покупку.", "A App Store não confirmou a compra.",
                                 "The App Store didn't confirm the purchase.")
                    return
                }
                await register(transaction)
                await transaction.finish()
            case .pending:
                message = tr("Покупка ждёт подтверждения (например, от родителей).",
                             "A compra aguarda aprovação.", "The purchase is waiting for approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// «Восстановить покупки» — обязательная кнопка по правилам App Store.
    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
            return
        }
        await syncEntitlements()
        if plan?.kind != .subscription {
            message = tr("Активных подписок не найдено.", "Não foram encontradas subscrições ativas.",
                         "No active subscriptions found.")
        }
    }

    private func syncEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            await register(transaction)
        }
    }

    private func register(_ transaction: Transaction) async {
        do {
            plan = try await RecapBackend.shared.verifySubscription(transactionID: transaction.originalID)
            Log.info(.app, "Recap Plus подтверждён сервером", detail: transaction.productID)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Промокод

    /// Откуда установлено приложение: из App Store — только коды Apple.
    func detectEnvironment() async {
        #if DEBUG
        ownPromoCodesAllowed = true
        #else
        if case .verified(let transaction) = try? await AppTransaction.shared {
            ownPromoCodesAllowed = transaction.environment != .production
        }
        #endif
    }

    /// Код Apple (Offer Code) оформляет обычную подписку — после его
    /// ввода остаётся свериться с App Store, как после покупки.
    func offerCodeRedeemed() async {
        await syncEntitlements()
    }

    func redeem(_ code: String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            plan = try await RecapBackend.shared.redeem(code: code)
            Log.info(.app, "Промокод принят")
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
