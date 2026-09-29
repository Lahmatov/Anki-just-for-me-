import SwiftUI
import AJFMCore

/// Ключи ИИ: какой провайдер работает и ключи к каждому.
///
/// Recap Plus ключей не требует; этот экран — для тех, кто хочет платить
/// провайдеру напрямую или уже пользуется Gemini, ChatGPT или Kimi.
struct AIKeysView: View {
    @State private var active = AIKeys.active

    var body: some View {
        List {
            Section {
                MascotSays(mood: .thinking,
                           text: tr("Выбери, чей ИИ подбирает слова и разбирает пересказы. Ключ "
                                        + "хранится только в Keychain телефона.",
                                    "Escolhe a IA que escolhe as palavras e analisa os recontos. "
                                        + "A chave fica só no Keychain do telemóvel.",
                                    "Pick whose AI chooses your words and reviews retellings. "
                                        + "The key stays in the phone's Keychain only."),
                           size: 64)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(AIProvider.allCases) { provider in
                    NavigationLink {
                        AIProviderKeyView(provider: provider, active: $active)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName).font(.app(.body, weight: .bold))
                                Text(status(provider))
                                    .font(.app(.caption))
                                    .foregroundStyle(AIKeys.key(for: provider) == nil
                                                     ? Theme.muted : Theme.green)
                            }
                            Spacer()
                            if provider == active {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.primary)
                                    .accessibilityLabel(tr("Выбран", "Escolhido", "Selected"))
                            }
                        }
                    }
                    .accessibilityIdentifier("aikeys.\(provider.rawValue)")
                }
            } footer: {
                Text(tr("Стоимость и месячный лимит приложение считает только для Claude. "
                            + "У остальных поставь лимит расходов в их консоли.",
                        "O custo e o limite mensal só são contados para o Claude. Nos outros, "
                            + "define o limite de gastos na consola deles.",
                        "Cost and the monthly limit are only tracked for Claude. For the others, "
                            + "set a spending limit in their console."))
            }
        }
        .themedScreen()
        .navigationTitle(tr("Ключи ИИ", "Chaves de IA", "AI keys"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { active = AIKeys.active }
    }

    private func status(_ provider: AIProvider) -> String {
        guard AIKeys.key(for: provider) != nil else {
            return tr("ключа нет", "sem chave", "no key")
        }
        return tr("ключ есть · ", "com chave · ", "key set · ") + AIKeys.model(for: provider)
    }
}

/// Один провайдер: ключ, модель, проверка и «использовать этот».
struct AIProviderKeyView: View {
    let provider: AIProvider
    @Binding var active: AIProvider

    @State private var key = ""
    @State private var model = ""
    @State private var checking = false
    @State private var checkResult: String?
    @State private var checkPassed = false

    var body: some View {
        Form {
            Section {
                SecureField(tr("Ключ API", "Chave da API", "API key"), text: $key)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: key) { _, value in
                        AIKeys.setKey(value, for: provider)
                        checkResult = nil
                    }
                Link(destination: provider.consoleURL) {
                    Label(tr("Где взять ключ", "Onde obter a chave", "Where to get a key"),
                          systemImage: "arrow.up.right.square")
                }
            } header: {
                Text(provider.displayName)
            }

            if provider != .anthropic {
                Section {
                    TextField(provider.defaultModel, text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: model) { _, value in AIKeys.setModel(value, for: provider) }
                } header: {
                    Text(tr("Модель", "Modelo", "Model"))
                } footer: {
                    Text(tr("Пусто — «\(provider.defaultModel)». Провайдеры переименовывают модели; "
                                + "если ключ верный, а запрос не проходит, впиши актуальную из их консоли.",
                            "Vazio — «\(provider.defaultModel)». Os fornecedores mudam os nomes dos "
                                + "modelos; se a chave está certa e o pedido falha, escreve o atual da consola.",
                            "Empty means “\(provider.defaultModel)”. Providers rename models; if the key "
                                + "is right but requests fail, enter the current one from their console."))
                }
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Label(tr("Проверить ключ", "Verificar a chave", "Check the key"),
                              systemImage: "checkmark.shield")
                        if checking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                if let checkResult {
                    Label(checkResult, systemImage: checkPassed ? "checkmark.circle.fill"
                                                               : "exclamationmark.triangle.fill")
                        .font(.app(.callout))
                        .foregroundStyle(checkPassed ? Theme.green : Theme.orange)
                }
            } footer: {
                Text(tr("Один крошечный запрос — стоит доли цента.",
                        "Um pedido minúsculo — custa uma fração de cêntimo.",
                        "One tiny request — costs a fraction of a cent."))
            }

            Section {
                Button {
                    AIKeys.active = provider
                    active = provider
                    Haptics.success()
                } label: {
                    Label(provider == active
                          ? tr("Используется", "Em uso", "In use")
                          : tr("Использовать \(provider.shortName)", "Usar \(provider.shortName)",
                               "Use \(provider.shortName)"),
                          systemImage: provider == active ? "checkmark.circle.fill" : "circle")
                }
                .disabled(provider == active || AIKeys.key(for: provider) == nil)

                if AIKeys.key(for: provider) != nil {
                    Button(tr("Удалить ключ", "Apagar a chave", "Delete the key"), role: .destructive) {
                        Keychain.remove(provider.keychainAccount)
                        key = ""
                        if active == provider {
                            AIKeys.active = .anthropic
                            active = .anthropic
                        }
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(provider.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            key = AIKeys.key(for: provider) ?? ""
            model = UserDefaults.standard.string(forKey: SettingsKey.aiModelPrefix + provider.rawValue) ?? ""
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            try await AIClient(provider: provider, apiKey: key).ping()
            checkPassed = true
            checkResult = tr("Ключ работает", "A chave funciona", "The key works")
        } catch {
            checkPassed = false
            checkResult = error.localizedDescription
        }
    }
}
