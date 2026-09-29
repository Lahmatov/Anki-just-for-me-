import SwiftUI
import PhotosUI
import StoreKit
import AuthenticationServices
import AJFMCore

/// Личный кабинет: профиль, вход через Apple, подписка, мои данные,
/// документы и поддержка — всё, что касается человека, а не учёбы.
///
/// Вход необязателен. Без него всё работает как раньше; вход нужен,
/// чтобы Recap Plus и промокод работали на всех телефонах человека.
struct AccountView: View {
    private var profile: ProfileStore { ProfileStore.shared }
    private var account: RecapAccount { RecapAccount.shared }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.englishLevel) private var storedLevel: String?

    @State private var nameDraft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showMascots = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var showManageSubscription = false
    @State private var nonce = ""
    @State private var photoError: String?
    @FocusState private var nameFocused: Bool

    static let refundURL = URL(string: "https://reportaproblem.apple.com")!

    var body: some View {
        List {
            headerSection
            if RecapBackend.isConfigured {
                signInSection
                plusSection
            }
            aiKeysSection
            dataSection
            documentsSection
            supportSection
        }
        .themedScreen()
        .navigationTitle(tr("Профиль", "Perfil", "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameDraft = profile.name }
        .task { await account.refresh() }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .sheet(isPresented: $showMascots) { mascotPicker }
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        .confirmationDialog(tr("Выйти из аккаунта?", "Terminar sessão?", "Sign out?"),
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(tr("Выйти", "Terminar sessão", "Sign out"), role: .destructive) {
                Task { await account.signOut() }
            }
            Button(CommonText.cancel, role: .cancel) {}
        } message: {
            Text(tr("Слова и прогресс останутся на телефоне. Доступ аккаунта (промокод, подписка "
                        + "с другого Apple ID) здесь пропадёт до следующего входа.",
                    "As palavras e o progresso ficam no telemóvel. O acesso da conta (código, "
                        + "subscrição de outro Apple ID) desaparece daqui até voltares a entrar.",
                    "Your words and progress stay on the phone. The account's access (promo code, "
                        + "a subscription from another Apple ID) leaves this phone until you sign in again."))
        }
        .confirmationDialog(tr("Удалить аккаунт?", "Apagar a conta?", "Delete your account?"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("Удалить аккаунт", "Apagar a conta", "Delete account"), role: .destructive) {
                Task {
                    if await account.deleteAccount() { Haptics.success() }
                }
            }
            Button(CommonText.cancel, role: .cancel) {}
        } message: {
            Text(tr("Аккаунт сотрётся на сервере, вход через Apple будет отозван, промокод аккаунта "
                        + "пропадёт. Подписку App Store это не отменяет — её отменяют в настройках "
                        + "Apple ID. Слова на телефоне останутся.",
                    "A conta é apagada no servidor, o início de sessão com a Apple é revogado e o "
                        + "código da conta desaparece. Isto não cancela a subscrição da App Store — "
                        + "isso faz-se nas definições do Apple ID. As palavras ficam no telemóvel.",
                    "The account is erased on the server, Sign in with Apple is revoked and the "
                        + "account's promo code is gone. This doesn't cancel an App Store subscription — "
                        + "do that in your Apple ID settings. Your words stay on the phone."))
        }
        .alert(CommonText.failedTitle,
               isPresented: Binding(get: { account.message != nil || photoError != nil },
                                    set: { if !$0 { account.message = nil; photoError = nil } })) {
            Button(CommonText.gotIt) { account.message = nil; photoError = nil }
        } message: {
            Text(photoError ?? account.message ?? "")
        }
    }

    // MARK: - Шапка

    private var headerSection: some View {
        Section {
            VStack(spacing: 14) {
                Menu {
                    Button(tr("Выбрать фото", "Escolher foto", "Choose a photo"),
                           systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                    Button(tr("Выбрать Мончика", "Escolher o Monchik", "Choose Monchik"),
                           systemImage: "face.smiling") { showMascots = true }
                    if profile.avatar != .initials {
                        Button(tr("Удалить аватарку", "Remover avatar", "Remove avatar"),
                               systemImage: "trash", role: .destructive) {
                            profile.resetAvatar()
                            Haptics.tap()
                        }
                    }
                } label: {
                    AvatarView(size: 96)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.onPrimary)
                                .padding(7)
                                .background(Theme.primary, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                        }
                }
                .accessibilityLabel(tr("Изменить аватарку", "Alterar avatar", "Change avatar"))

                TextField(tr("Как тебя зовут?", "Como te chamas?", "What's your name?"), text: $nameDraft)
                    .font(.app(.title3, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { profile.setName(nameDraft); nameDraft = profile.name }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { profile.setName(nameDraft); nameDraft = profile.name }
                    }

                HStack(spacing: 8) {
                    chip(storedLevel.map { tr("Уровень ", "Nível ", "Level ") + $0 }
                         ?? tr("Уровень не выбран", "Nível por definir", "Level not set"),
                         symbol: "graduationcap.fill", color: Theme.blue)
                    if account.plan?.active == true {
                        chip(account.plan?.kind == .subscription ? "Recap Plus"
                                : tr("Промокод", "Código", "Promo"),
                             symbol: "star.fill", color: Theme.gold)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } footer: {
            Text(tr("Имя и аватарка хранятся только на этом телефоне.",
                    "O nome e o avatar ficam só neste telemóvel.",
                    "Your name and avatar are stored on this phone only."))
                .frame(maxWidth: .infinity)
        }
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.app(.caption, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var mascotPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 16) {
                    ForEach(MascotMood.allCases, id: \.self) { mood in
                        Button {
                            profile.setMascot(mood)
                            Haptics.success()
                            showMascots = false
                        } label: {
                            Image(mood.assetName)
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                                .frame(width: 96, height: 96)
                                .background(Theme.tint, in: Circle())
                                .overlay(Circle().strokeBorder(
                                    profile.avatar == .mascot(mood) ? Theme.primary : Theme.border,
                                    lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Mascot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { showMascots = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ProfileStore.Failure.unreadableImage
            }
            try profile.setPhoto(data)
            Haptics.success()
        } catch {
            Log.failure(.app, "Фото профиля не сохранилось", error)
            photoError = ProfileStore.Failure.unreadableImage.localizedDescription
        }
    }

    // MARK: - Вход

    @ViewBuilder
    private var signInSection: some View {
        Section {
            if account.signedIn {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Вход через Apple", "Sessão iniciada com a Apple", "Signed in with Apple"))
                            .font(.app(.body, weight: .bold))
                        Text(tr("Доступ работает на всех твоих телефонах",
                                "O acesso funciona em todos os teus telemóveis",
                                "Your access works on all your phones"))
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                } icon: {
                    Image(systemName: "apple.logo").foregroundStyle(Theme.ink)
                }
                Button(tr("Выйти", "Terminar sessão", "Sign out")) { confirmSignOut = true }
                    .disabled(account.busy)
                Button(tr("Удалить аккаунт", "Apagar a conta", "Delete account"), role: .destructive) {
                    confirmDelete = true
                }
                .disabled(account.busy)
            } else if AppleSignIn.isEnabled {
                SignInWithAppleButton(.signIn) { request in
                    let fresh = AppleSignIn.makeNonce()
                    nonce = fresh
                    // Почту не спрашиваем: она не нужна ни серверу, ни приложению.
                    request.requestedScopes = [.fullName]
                    request.nonce = AppleSignIn.sha256(fresh)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        do {
                            let signIn = try AppleSignIn.result(from: authorization, nonce: nonce)
                            Task {
                                if await account.signIn(signIn) {
                                    nameDraft = profile.name
                                    Haptics.success()
                                }
                            }
                        } catch {
                            account.message = error.localizedDescription
                        }
                    case .failure(let error):
                        account.message = AppleSignIn.failure(from: error).errorDescription
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(account.busy)
            } else {
                Label(tr("Вход через Apple появится в сборке для App Store.",
                         "O início de sessão com a Apple chega na versão da App Store.",
                         "Sign in with Apple arrives in the App Store build."),
                      systemImage: "apple.logo")
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(tr("Аккаунт", "Conta", "Account"))
        } footer: {
            if !account.signedIn {
                Text(tr("Вход не обязателен. Он нужен, чтобы Recap Plus и промокод работали на всех "
                            + "твоих телефонах. Слова и прогресс остаются на телефоне; серверу не "
                            + "передаются ни имя, ни почта.",
                        "Iniciar sessão é opcional. Serve para o Recap Plus e o código funcionarem em "
                            + "todos os teus telemóveis. As palavras ficam no telemóvel; o servidor não "
                            + "recebe nome nem e-mail.",
                        "Signing in is optional. It lets Recap Plus and promo codes work on all your "
                            + "phones. Words and progress stay on the phone; the server gets neither "
                            + "your name nor your e-mail."))
            }
        }
    }

    // MARK: - Подписка

    private var plusSection: some View {
        Section {
            NavigationLink {
                PlusView()
            } label: {
                HStack(spacing: 14) {
                    IconBadge(systemName: "star.fill", color: Theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recap Plus").font(.app(.body, weight: .bold))
                        Text(plusSubtitle).font(.app(.caption)).foregroundStyle(Theme.muted)
                    }
                }
            }
            if account.plan?.kind == .subscription {
                Button(tr("Управлять подпиской", "Gerir subscrição", "Manage subscription"),
                       systemImage: "creditcard") { showManageSubscription = true }
                Link(destination: Self.refundURL) {
                    Label(tr("Запросить возврат", "Pedir reembolso", "Request a refund"),
                          systemImage: "arrow.uturn.backward.circle")
                }
            }
        } header: {
            Text(tr("Подписка", "Subscrição", "Subscription"))
        } footer: {
            if account.plan?.kind == .subscription {
                Text(tr("Оплату, отмену и возвраты ведёт Apple.",
                        "Pagamentos, cancelamentos e reembolsos são geridos pela Apple.",
                        "Apple handles payment, cancellation and refunds."))
            }
        }
    }

    private var plusSubtitle: String {
        guard let plan = account.plan, plan.active else {
            return tr("Подписка и промокоды", "Subscrição e códigos", "Subscription and promo codes")
        }
        return tr("Активен · осталось ≈ ", "Ativo · resta ≈ ", "Active · ≈ ")
            + Counted.decks(plan.approximateDecksLeft)
            + tr("", "", " left")
    }

    // MARK: - Ключи ИИ

    private var aiKeysSection: some View {
        Section {
            NavigationLink {
                AIKeysView()
            } label: {
                HStack(spacing: 14) {
                    IconBadge(systemName: "key.fill", color: Theme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Ключи ИИ", "Chaves de IA", "AI keys")).font(.app(.body, weight: .bold))
                        Text(AIKeys.hasActiveKey
                             ? tr("Работает: ", "Em uso: ", "In use: ") + AIKeys.active.shortName
                             : tr("Claude, Gemini, ChatGPT, Kimi и другие",
                                  "Claude, Gemini, ChatGPT, Kimi e outros",
                                  "Claude, Gemini, ChatGPT, Kimi and more"))
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .accessibilityIdentifier("profile.aikeys")
        } footer: {
            Text(tr("Свой ключ — если не хочешь подписку: платишь провайдеру напрямую.",
                    "Chave própria — se não queres subscrição: pagas diretamente ao fornecedor.",
                    "Your own key — if you'd rather skip the subscription and pay the provider directly."))
        }
    }

    // MARK: - Данные

    private var dataSection: some View {
        Section {
            if RecapBackend.isConfigured {
                NavigationLink {
                    ServerDataView()
                } label: {
                    Label(tr("Мои данные на сервере", "Os meus dados no servidor", "My data on the server"),
                          systemImage: "server.rack")
                }
            }
            NavigationLink {
                PrivacyView()
            } label: {
                Label(tr("Конфиденциальность и удаление данных", "Privacidade e apagar dados",
                         "Privacy and data deletion"),
                      systemImage: "hand.raised")
            }
        } header: {
            Text(tr("Мои данные", "Os meus dados", "My data"))
        } footer: {
            Text(tr("Копия слов и прогресса — бэкап на вкладке «Наборы».",
                    "A cópia das palavras e do progresso é o backup no separador «Baralhos».",
                    "A copy of your words and progress is the backup on the Decks tab."))
        }
    }

    // MARK: - Документы

    private var documentsSection: some View {
        Section(tr("Документы", "Documentos", "Documents")) {
            ForEach(LegalDocument.Kind.allCases) { kind in
                NavigationLink {
                    LegalDocumentView(kind: kind)
                } label: {
                    Label(kind.title, systemImage: symbol(for: kind))
                }
                .accessibilityIdentifier("docs.\(kind.rawValue)")
            }
            NavigationLink {
                SellerInfoView()
            } label: {
                Label(tr("О продавце", "Sobre o vendedor", "About the trader"),
                      systemImage: "building.2")
            }
        }
    }

    private func symbol(for kind: LegalDocument.Kind) -> String {
        switch kind {
        case .terms: return "doc.text"
        case .privacy: return "lock.shield"
        case .licenses: return "text.book.closed"
        }
    }

    // MARK: - Поддержка

    private var supportSection: some View {
        Section {
            NavigationLink {
                MonchikHelpView()
            } label: {
                Label("Monchik Help", systemImage: "questionmark.bubble")
            }
            .accessibilityIdentifier("profile.help")
            if let url = SupportContact.mailURL {
                Button {
                    openURL(url)
                } label: {
                    Label(tr("Написать в поддержку", "Contactar o suporte", "Contact support"),
                          systemImage: "envelope")
                }
            }
            Button {
                requestReview()
            } label: {
                Label(tr("Оценить приложение", "Avaliar a aplicação", "Rate the app"),
                      systemImage: "star.bubble")
            }
            LabeledContent(tr("Версия", "Versão", "Version"), value: Self.version)
        } header: {
            Text(tr("Поддержка", "Suporte", "Support"))
        } footer: {
            if let code = account.supportCode {
                Text(tr("Код поддержки: ", "Código de suporte: ", "Support code: ") + code
                     + tr(" — назови его в письме, по нему находится запись на сервере.",
                          " — indica-o no e-mail; é assim que se encontra o registo no servidor.",
                          " — mention it in your e-mail; it's how we find your record on the server."))
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
