import SwiftUI
import SwiftData
import UIKit
import AJFMCore

/// Письмо в поддержку: адрес продавца, версия, iOS и код поддержки.
enum SupportContact {
    @MainActor
    static var mailURL: URL? {
        guard let email = LegalInfo.seller.contactEmail else { return nil }
        let body = SupportMail.body(appVersion: AccountView.version,
                                    systemVersion: UIDevice.current.systemVersion,
                                    supportCode: RecapAccount.shared.supportCode,
                                    language: Loc.language)
        return SupportMail.url(to: email, subject: "Monchik Help — Recap", body: body)
    }
}

/// Monchik Help: частые вопросы, «Спросить Мончика» и письмо человеку.
struct MonchikHelpView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    private var help: HelpService { HelpService.shared }

    var body: some View {
        List {
            Section {
                MascotSays(mood: .hello,
                           text: tr("Спрашивай! Сначала загляни в частые вопросы — там ответ "
                                        + "мгновенно. Нет ответа — спроси меня или напиши человеку.",
                                    "Pergunta! Vê primeiro as perguntas frequentes — a resposta é "
                                        + "imediata. Sem resposta? Pergunta-me ou escreve a uma pessoa.",
                                    "Ask away! Check the FAQ first — answers are instant. Nothing "
                                        + "there? Ask me or write to a human."),
                           size: 64)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            faqSection
            askSection
            contactSection

            Section {
                NavigationLink {
                    WhySeriesView()
                } label: {
                    Label(tr("Почему сериалы работают", "Porque é que as séries funcionam",
                             "Why TV shows work"),
                          systemImage: "book.pages")
                }
            }
        }
        .themedScreen()
        .searchable(text: $query, prompt: tr("Поиск по вопросам", "Procurar nas perguntas", "Search the FAQ"))
        .navigationTitle("Monchik Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Частые вопросы

    private var faqSection: some View {
        let results = HelpCenter.search(query)
        return Section(tr("Частые вопросы", "Perguntas frequentes", "FAQ")) {
            if results.isEmpty {
                Text(tr("Такого вопроса нет — спроси Мончика ниже.",
                        "Não há essa pergunta — pergunta ao Monchik abaixo.",
                        "No such question — ask Monchik below."))
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(results) { entry in
                DisclosureGroup {
                    Text(entry.answer)
                        .font(.app(.callout))
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 4)
                } label: {
                    Text(entry.question).font(.app(.body, weight: .bold))
                }
            }
        }
    }

    // MARK: - Спросить Мончика

    @ViewBuilder
    private var askSection: some View {
        Section {
            ForEach(help.messages) { message in
                bubble(message)
            }
            if help.waiting {
                HStack(spacing: 8) {
                    MonchikLoader()
                    Text(tr("Мончик думает… Можно свернуть приложение — ответ придёт уведомлением.",
                            "O Monchik está a pensar… Podes sair da aplicação — a resposta chega "
                                + "numa notificação.",
                            "Monchik is thinking… You can leave the app — the answer arrives as a "
                                + "notification."))
                        .font(.app(.caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            if let error = help.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.app(.caption))
                    .foregroundStyle(Theme.orange)
            }
            if help.canAsk {
                HStack(spacing: 8) {
                    TextField(tr("Твой вопрос о приложении", "A tua pergunta sobre a aplicação",
                                 "Your question about the app"),
                              text: $question, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($questionFocused)
                        .accessibilityIdentifier("help.question")
                    Button {
                        let text = question
                        question = ""
                        questionFocused = false
                        Task { await help.ask(text, context: context) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(HelpChat.cleanQuestion(question) == nil || help.waiting)
                    .accessibilityLabel(tr("Отправить", "Enviar", "Send"))
                }
            } else {
                Text(tr("Спросить Мончика можно, когда подключён сервер Recap или есть свой ключ ИИ.",
                        "Podes perguntar ao Monchik quando o servidor Recap estiver ligado ou "
                            + "tiveres uma chave de IA.",
                        "You can ask Monchik once the Recap server is connected or you have an AI key."))
                    .font(.app(.caption))
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            HStack {
                Text(tr("Спросить Мончика", "Perguntar ao Monchik", "Ask Monchik"))
                Spacer()
                if !help.messages.isEmpty {
                    Button(tr("Очистить", "Limpar", "Clear")) { help.clear() }
                        .font(.app(.caption, weight: .bold))
                        .textCase(nil)
                }
            }
        } footer: {
            Text(tr("Мончик — ИИ и отвечает только о Recap. Может ошибаться; важное — письмом человеку.",
                    "O Monchik é uma IA e só responde sobre o Recap. Pode enganar-se; o importante — "
                        + "por e-mail a uma pessoa.",
                    "Monchik is an AI and only answers about Recap. He can be wrong; for anything "
                        + "important, e-mail a human."))
        }
    }

    @ViewBuilder
    private func bubble(_ message: HelpChat.Message) -> some View {
        switch message.author {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.app(.callout))
                    .padding(10)
                    .background(Theme.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .monchik:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    MascotView(mood: .hello, size: 30)
                    Text(message.text)
                        .font(.app(.callout))
                        .textSelection(.enabled)
                }
                if message.suggestEmail, let url = SupportContact.mailURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label(tr("Написать человеку", "Escrever a uma pessoa", "Write to a human"),
                              systemImage: "envelope")
                            .font(.app(.caption, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Письмо

    private var contactSection: some View {
        Section {
            if let url = SupportContact.mailURL {
                Button {
                    openURL(url)
                } label: {
                    Label(tr("Написать в поддержку", "Escrever ao suporte", "E-mail support"),
                          systemImage: "envelope")
                }
            } else {
                Label(tr("Адрес поддержки ещё не указан", "O e-mail do suporte ainda não está definido",
                         "The support e-mail isn't set yet"),
                      systemImage: "envelope.badge")
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(tr("Человек", "Uma pessoa", "A human"))
        } footer: {
            if let code = RecapAccount.shared.supportCode {
                Text(tr("В письмо сразу попадут версия приложения и код поддержки \(code).",
                        "O e-mail já leva a versão da aplicação e o código de suporte \(code).",
                        "The e-mail already includes the app version and support code \(code)."))
            }
        }
    }
}
