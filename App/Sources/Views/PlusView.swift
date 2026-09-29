import SwiftUI
import StoreKit
import AJFMCore

/// Recap Plus: что даёт подписка, покупка, промокод и остаток лимита.
///
/// По правилам App Store на экране подписки обязательны цена и срок,
/// «Восстановить покупки», условия использования и политика
/// конфиденциальности — всё это здесь.
struct PlusView: View {
    private var account: RecapAccount { RecapAccount.shared }

    @State private var code = ""
    @State private var redeemed = false
    @State private var showOfferCode = false
    @FocusState private var codeFocused: Bool

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        List {
            Section {
                MascotSays(mood: .cheer,
                           text: tr("С Recap Plus я сам подберу слова к любой серии и поговорю с тобой о ней.",
                                    "Com o Recap Plus escolho palavras para qualquer episódio e converso contigo sobre ele.",
                                    "With Recap Plus I'll pick words for any episode and chat with you about it."),
                           size: 80)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if let plan = account.plan, plan.kind != .none {
                statusSection(plan)
            }

            Section(tr("Что входит", "O que inclui", "What's included")) {
                feature("sparkles", tr("Слова к любой серии любого сериала — без своего ключа",
                                       "Palavras para qualquer episódio — sem chave própria",
                                       "Words for any episode of any show — no key needed"))
                feature("bubble.left.and.bubble.right.fill",
                        tr("Разговор с Мончиком о каждой серии, к которой взяты слова",
                           "Conversa com o Monchik sobre cada episódio com palavras",
                           "Chat with Monchik about every episode you took words for"))
                feature("books.vertical.fill", tr("Готовые наборы к популярным сериалам — бесплатно всем",
                                                  "Baralhos prontos de séries populares — grátis para todos",
                                                  "Ready decks for popular shows — free for everyone"))
            }

            if account.plan?.kind != .subscription {
                productsSection
            }

            if account.ownPromoCodesAllowed {
                promoSection
            } else {
                Section {
                    Button(tr("Ввести код предложения", "Resgatar código de oferta", "Redeem an offer code")) {
                        showOfferCode = true
                    }
                } footer: {
                    Text(tr("Коды выдаёт App Store; подписка по коду оформляется как обычная.",
                            "Os códigos são da App Store; a subscrição fica como uma normal.",
                            "Codes come from the App Store; they start a regular subscription."))
                }
            }

            Section {
                Button(tr("Восстановить покупки", "Restaurar compras", "Restore purchases")) {
                    Task { await account.restore() }
                }
                .disabled(account.busy)
                // Документы — прямо в приложении: правило 3.1.2 требует рабочих
                // ссылок на экране подписки, и без сети они тоже должны открываться.
                NavigationLink(LegalDocument.Kind.terms.title) {
                    LegalDocumentView(kind: .terms)
                }
                NavigationLink(LegalDocument.Kind.privacy.title) {
                    LegalDocumentView(kind: .privacy)
                }
                Link(tr("Стандартное лицензионное соглашение Apple", "Contrato de licença padrão da Apple",
                        "Apple's Standard License Agreement"),
                     destination: Self.termsURL)
            } footer: {
                Text(tr("Подписка продлевается автоматически, если не отменить её хотя бы за сутки "
                            + "до конца периода. Управлять — в настройках Apple ID.",
                        "A subscrição renova-se automaticamente, salvo se for cancelada pelo menos "
                            + "24 horas antes do fim do período. Gere-a nas definições do Apple ID.",
                        "The subscription renews automatically unless cancelled at least 24 hours "
                            + "before the period ends. Manage it in your Apple ID settings."))
            }
        }
        .themedScreen()
        .navigationTitle("Recap Plus")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await account.detectEnvironment()
            await account.loadProducts()
            await account.refresh()
        }
        .offerCodeRedemption(isPresented: $showOfferCode) { _ in
            Task { await account.offerCodeRedeemed() }
        }
        .alert(CommonText.failedTitle,
               isPresented: Binding(get: { account.message != nil },
                                    set: { if !$0 { account.message = nil } })) {
            Button(CommonText.gotIt) { account.message = nil }
        } message: {
            Text(account.message ?? "")
        }
    }

    private func statusSection(_ plan: BackendAPI.PlanStatus) -> some View {
        Section(tr("Твой доступ", "O teu acesso", "Your access")) {
            LabeledContent(tr("Тариф", "Plano", "Plan"),
                           value: plan.kind == .subscription ? "Recap Plus"
                                : tr("Промокод", "Código promocional", "Promo code"))
            if let end = plan.periodEndDate {
                LabeledContent(plan.active ? tr("Действует до", "Válido até", "Valid until")
                                           : tr("Закончился", "Terminou", "Ended"),
                               value: end.formatted(date: .abbreviated, time: .omitted))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Осталось в этом периоде: ≈ ", "Resta neste período: ≈ ", "Left this period: ≈ ")
                     + Counted.decks(plan.approximateDecksLeft))
                    .font(.app(.callout, weight: .bold))
                ChunkyProgressBar(value: plan.fractionLeft, height: 12)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        Section {
            if account.products.isEmpty {
                HStack {
                    MonchikLoader()
                    Text(tr("Загружаю цены…", "A carregar preços…", "Loading prices…"))
                        .foregroundStyle(Theme.muted)
                }
            }
            ForEach(account.products, id: \.id) { product in
                Button {
                    Task { await account.purchase(product) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.app(.headline))
                            Text(period(of: product)).font(.app(.caption))
                        }
                        Spacer()
                        Text(product.displayPrice).font(.app(.headline))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky)
                .disabled(account.busy)
                .listRowBackground(Color.clear)
            }
        } header: {
            Text(tr("Подписка", "Subscrição", "Subscription"))
        }
    }

    private var promoSection: some View {
        Section {
            TextField("RECAP-XXXX-XXXX-XXXX-XXXX", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .focused($codeFocused)
            Button(tr("Активировать", "Ativar", "Redeem")) {
                codeFocused = false
                Task {
                    if await account.redeem(code) {
                        code = ""
                        redeemed = true
                        Haptics.success()
                    } else {
                        Haptics.failure()
                    }
                }
            }
            .disabled(code.trimmingCharacters(in: .whitespaces).count < 16 || account.busy)
            if redeemed {
                Label(tr("Код принят!", "Código aceite!", "Code accepted!"),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.green)
            }
        } header: {
            Text(tr("Промокод", "Código promocional", "Promo code"))
        } footer: {
            Text(tr("Код проверяет сервер; каждый можно использовать один раз.",
                    "O código é verificado pelo servidor; cada um só pode ser usado uma vez.",
                    "The server checks the code; each one works only once."))
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.app(.callout))
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.primary)
        }
    }

    private func period(of product: Product) -> String {
        guard let unit = product.subscription?.subscriptionPeriod.unit else { return "" }
        switch unit {
        case .month: return tr("в месяц", "por mês", "per month")
        case .year: return tr("в год", "por ano", "per year")
        case .week: return tr("в неделю", "por semana", "per week")
        default: return ""
        }
    }
}
