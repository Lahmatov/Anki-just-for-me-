import SwiftUI
import SwiftData
import AJFMCore

/// Конфиденциальность: политика прямо в приложении и удаление всех данных.
///
/// Политика нужна App Store дважды — ссылкой в App Store Connect и внутри
/// приложения. Здесь она текстом, а не только ссылкой: читается без сети
/// и всегда совпадает с тем, что приложение делает в этой версии.
/// Опубликованная копия — docs/privacy-policy.md.
struct PrivacyView: View {
    @Environment(\.modelContext) private var context

    @State private var confirmErase = false
    @State private var eraseCloud = true
    @State private var erasing = false
    @State private var erased = false
    @State private var eraseError: String?
    @State private var aiConsent = AIConsent.isGiven

    /// Публичный адрес политики — для App Store Connect и кнопки ниже.
    static let policyURL = URL(
        string: "https://github.com/lahmatov/Anki-just-for-me-/blob/main/docs/privacy-policy.md")!

    var body: some View {
        List {
            Section {
                MascotSays(mood: .hello,
                           text: tr("Твои слова живут на твоём телефоне. Я никому их не отдаю.",
                                    "As tuas palavras vivem no teu telemóvel. Não as dou a ninguém.",
                                    "Your words live on your phone. I don't hand them to anyone."),
                           size: 72)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section(tr("Что хранится", "O que é guardado", "What is stored")) {
                point("iphone", tr("Только на телефоне: слова, карточки, история повторов, "
                                      + "пересказы, цели и настройки. Аккаунтов нет.",
                                   "Só no telemóvel: palavras, cartões, histórico, recontos, "
                                      + "objetivos e definições. Não há contas.",
                                   "On the phone only: words, cards, review history, retellings, "
                                      + "goals and settings. There are no accounts."))
                point("mic", tr("Запись голоса для произношения и пересказа не сохраняется: "
                                   + "из неё берётся только текст. Распознавание идёт на "
                                   + "телефоне, где iOS это умеет; иначе — сервисом Apple.",
                                "A gravação de voz não é guardada: só se usa o texto. O "
                                   + "reconhecimento corre no telemóvel quando o iOS o permite; "
                                   + "senão, no serviço da Apple.",
                                "Voice recordings aren't kept — only the text is used. "
                                   + "Recognition runs on the phone where iOS supports it; "
                                   + "otherwise Apple's service handles it."))
                point("key", tr("Ключи API и строка подключения к облаку — в Keychain.",
                                "As chaves da API e a ligação à nuvem ficam no Keychain.",
                                "API keys and the cloud connection string are kept in the Keychain."))
            }

            Section(tr("Что и куда уходит", "O que sai e para onde", "What leaves the phone")) {
                point("sparkles", tr("Anthropic (Claude) — только когда ты сам просишь набор или "
                                        + "разбор: текст запроса, субтитры, текст пересказа и список "
                                        + "уже известных слов. По твоему ключу.",
                                     "Anthropic (Claude) — só quando pedes um baralho ou uma "
                                        + "análise: o pedido, as legendas, o texto do reconto e a "
                                        + "lista de palavras conhecidas. Com a tua chave.",
                                     "Anthropic (Claude) — only when you ask for a deck or a review: "
                                        + "your request, subtitles, the retelling text and the list "
                                        + "of known words. Using your own key."))
                point("server.rack", tr("Сервер Recap — только с подпиской или промокодом: номер серии, "
                                           + "язык, уровень, известные слова и реплики разговора. Сервер "
                                           + "передаёт их в Anthropic и не хранит; в базе — только "
                                           + "случайный номер устройства и расход.",
                                        "Servidor Recap — só com subscrição ou código: número do "
                                           + "episódio, idioma, nível, palavras conhecidas e falas da "
                                           + "conversa. O servidor envia-os à Anthropic e não os guarda; "
                                           + "na base só fica um número aleatório do dispositivo e o consumo.",
                                        "Recap server — only with a subscription or promo code: the "
                                           + "episode number, language, level, known words and chat "
                                           + "lines. The server passes them to Anthropic and doesn't "
                                           + "keep them; it stores only a random device ID and usage."))
                point("icloud.and.arrow.up", tr("Neon — копия базы раз в сутки, если ты сам "
                                                   + "подключил свою базу данных.",
                                                "Neon — uma cópia da base por dia, se ligaste a "
                                                   + "tua própria base de dados.",
                                                "Neon — a daily copy of the database, only if you "
                                                   + "connected your own database."))
                point("tv", tr("TVMaze — название сериала, чтобы найти постер и название серии.",
                               "TVMaze — o nome da série, para encontrar o cartaz e o episódio.",
                               "TVMaze — the show name, to find its poster and episode title."))
                point("hand.raised", tr("Нет рекламы, аналитики, трекинга и сторонних SDK. "
                                           + "Данные не продаются и не передаются для рекламы.",
                                        "Sem publicidade, análise, rastreio nem SDKs de terceiros. "
                                           + "Os dados não são vendidos nem partilhados para anúncios.",
                                        "No ads, analytics, tracking or third-party SDKs. Data is "
                                           + "never sold or shared for advertising."))
            }

            Section {
                Toggle(tr("Разрешить отправку в Claude", "Permitir envio ao Claude",
                          "Allow sending to Claude"), isOn: $aiConsent)
                    .onChange(of: aiConsent) { _, value in AIConsent.isGiven = value }
            } footer: {
                Text(tr("Без разрешения наборы через Claude и разборы пересказов спросят "
                            + "его перед отправкой.",
                        "Sem autorização, os baralhos com o Claude e as análises pedem-na "
                            + "antes de enviar.",
                        "Without it, Claude decks and retelling reviews will ask before sending."))
            }

            Section {
                Link(destination: Self.policyURL) {
                    Label(tr("Полный текст политики", "Texto completo da política",
                             "Full privacy policy"),
                          systemImage: "doc.text")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmErase = true
                } label: {
                    HStack {
                        Label(tr("Удалить все данные", "Apagar todos os dados", "Delete all data"),
                              systemImage: "trash")
                        if erasing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(erasing)
                if CloudBackupService.isConfigured {
                    Toggle(tr("И копии в облаке", "E as cópias na nuvem", "And the cloud copies"),
                           isOn: $eraseCloud)
                }
            } footer: {
                Text(tr("Удаляются слова, прогресс, цели, расходы, ключи, настройки и бэкапы. "
                            + "Отменить нельзя — сначала можно сохранить бэкап на вкладке «Наборы».",
                        "Apaga palavras, progresso, objetivos, custos, chaves, definições e cópias. "
                            + "Não dá para desfazer — guarda antes uma cópia em «Baralhos».",
                        "Deletes words, progress, goals, costs, keys, settings and backups. "
                            + "This can't be undone — save a backup on the Decks tab first."))
            }
        }
        .themedScreen()
        .navigationTitle(tr("Конфиденциальность", "Privacidade", "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            tr("Удалить все данные?", "Apagar todos os dados?", "Delete all data?"),
            isPresented: $confirmErase, titleVisibility: .visible
        ) {
            Button(tr("Удалить навсегда", "Apagar para sempre", "Delete forever"),
                   role: .destructive) {
                Task { await erase() }
            }
            Button(CommonText.cancel, role: .cancel) {}
        }
        .alert(tr("Готово", "Feito", "Done"), isPresented: $erased) {
            Button(CommonText.ok) {}
        } message: {
            Text(tr("Все данные удалены. Приложение как после установки.",
                    "Todos os dados foram apagados. A aplicação está como nova.",
                    "All data deleted. The app is as good as freshly installed."))
        }
        .alert(CommonText.failedTitle,
               isPresented: Binding(get: { eraseError != nil }, set: { if !$0 { eraseError = nil } }),
               presenting: eraseError) { _ in
            Button(CommonText.gotIt) {}
        } message: { Text($0) }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.app(.callout))
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.primary)
        }
    }

    private func erase() async {
        erasing = true
        defer { erasing = false }
        // Облако — первым: после удаления ключей до него уже не достучаться.
        if eraseCloud, CloudBackupService.isConfigured {
            do {
                try await CloudBackupService(context: context).eraseAll()
            } catch {
                Log.failure(.backup, "Снимки в облаке не удалились", error)
                eraseError = tr("Копии в облаке не удалились: \(error.localizedDescription). "
                                    + "Локальные данные не тронуты — попробуй ещё раз.",
                                "As cópias na nuvem não foram apagadas: \(error.localizedDescription). "
                                    + "Os dados locais estão intactos — tenta de novo.",
                                "Cloud copies weren't deleted: \(error.localizedDescription). "
                                    + "Local data is untouched — try again.")
                return
            }
        }
        // Сервер Recap — тоже до ключей: без токена устройство там не найти.
        if RecapBackend.isConfigured {
            do {
                try await RecapBackend.shared.forgetDevice()
            } catch {
                Log.failure(.network, "Устройство на сервере Recap не удалилось", error)
                eraseError = tr("Данные на сервере Recap не удалились: \(error.localizedDescription). "
                                    + "Локальные данные не тронуты — попробуй ещё раз.",
                                "Os dados no servidor Recap não foram apagados: \(error.localizedDescription). "
                                    + "Os dados locais estão intactos — tenta de novo.",
                                "Recap server data wasn't deleted: \(error.localizedDescription). "
                                    + "Local data is untouched — try again.")
                return
            }
        }
        do {
            try DataEraseService(context: context).eraseEverythingLocal()
            Haptics.success()
            erased = true
        } catch {
            Log.failure(.app, "Данные не удалились", error)
            eraseError = error.localizedDescription
        }
    }
}
