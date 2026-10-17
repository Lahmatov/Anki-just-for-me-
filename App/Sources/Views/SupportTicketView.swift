import SwiftUI
import SwiftData
import UIKit
import AJFMCore

/// Обращение в поддержку (P-72): категория, текст, почта по желанию и
/// диагностика — версии и языки, без слов и прогресса. Ответ придёт в
/// «Мои обращения», а если оставить почту — и письмом.
struct SupportTicketView: View {
    @Environment(\.modelContext) private var context
    @State private var model = SupportTicketViewModel()

    var body: some View {
        Form {
            if let sent = model.sent {
                Section {
                    MascotSays(mood: .cheer,
                               text: tr("Получил! Номер обращения \(sent.id). Ответ появится в «Мои обращения».",
                                        "Recebido! Pedido n.º \(sent.id). A resposta aparece em «Os meus pedidos».",
                                        "Got it! Request \(sent.id). The answer will appear in My requests."),
                               size: 64)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("support.sent")
                }
            } else {
                Section(tr("О чём", "Sobre o quê", "About")) {
                    Picker(tr("Тема", "Tema", "Topic"), selection: $model.category) {
                        ForEach(SupportCategory.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    .accessibilityIdentifier("support.category")
                }
                Section {
                    TextField(tr("Например: диктант молчит на iPad", "Por exemplo: o ditado não fala no iPad",
                                 "For example: dictation is silent on iPad"),
                              text: $model.message, axis: .vertical)
                        .lineLimit(6...)
                        .accessibilityIdentifier("support.message")
                } header: {
                    Text(tr("Что случилось", "O que aconteceu", "What happened"))
                } footer: {
                    Text(tr("Чем подробнее, тем быстрее: что делал, что ждал, что увидел.",
                            "Quanto mais detalhe, mais rápido: o que fizeste, o que esperavas, o que viste.",
                            "The more detail, the faster: what you did, expected and saw."))
                }
                Section {
                    TextField(tr("Почта (необязательно)", "E-mail (opcional)", "E-mail (optional)"), text: $model.contact)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("support.contact")
                    Toggle(tr("Приложить диагностику", "Anexar diagnóstico", "Attach diagnostics"),
                           isOn: $model.attachDiagnostics)
                } footer: {
                    Text(model.attachDiagnostics
                         ? tr("Уйдут: ", "Vai: ", "Sent: ") + model.diagnosticsSummary
                         : tr("Без диагностики, возможно, придётся переспросить версию.",
                              "Sem diagnóstico, talvez tenhamos de perguntar a versão.",
                              "Without diagnostics we may need to ask for your version."))
                }
                if let error = model.error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.orange) }
                }
                Section {
                    Button(action: send) {
                        HStack {
                            if model.sending { MonchikLoader() }
                            Text(tr("Отправить", "Enviar", "Send")).font(.app(.headline))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!model.canSend)
                    .accessibilityIdentifier("support.send")
                } footer: {
                    Text(tr("Обращение хранится год после ответа и удаляется вместе с данными. "
                                + "Подробно — в политике конфиденциальности.",
                            "O pedido fica guardado um ano após a resposta e é apagado com os dados. "
                                + "Detalhes na política de privacidade.",
                            "Requests are kept for a year after the answer and deleted with your data. "
                                + "Details in the privacy policy."))
                }
            }
        }
        .themedScreen()
        .navigationTitle(tr("Поддержка", "Suporte", "Support"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.loadDiagnostics(in: context) }
    }

    private func send() {
        Task { await model.send() }
    }
}

/// «Мои обращения»: номер, статус и ответ поддержки.
struct SupportTicketsView: View {
    @State private var model = SupportTicketsViewModel()

    var body: some View {
        List {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.orange)
            }
            if let tickets = model.tickets, tickets.isEmpty {
                Text(tr("Обращений пока нет.", "Ainda não há pedidos.", "No requests yet."))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(model.tickets ?? []) { ticket in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(ticket.kind.title, systemImage: ticket.kind.symbol)
                            .font(.app(.caption, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text(ticket.id).font(.app(.caption).monospaced()).foregroundStyle(Theme.muted)
                    }
                    Text(ticket.message).font(.app(.callout)).foregroundStyle(Theme.ink).lineLimit(4)
                    if let reply = ticket.reply, !reply.isEmpty {
                        Label(reply, systemImage: "arrowshape.turn.up.left.fill")
                            .font(.app(.body))
                            .foregroundStyle(Theme.ink)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panel(fill: Theme.green.opacity(0.1), border: Theme.green.opacity(0.5), lip: false,
                                   radius: 12)
                    } else {
                        Text(ticket.status == "closed" ? tr("Закрыто", "Fechado", "Closed")
                                                      : tr("Ждёт ответа", "À espera de resposta", "Waiting for an answer"))
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .themedScreen()
        .navigationTitle(tr("Мои обращения", "Os meus pedidos", "My requests"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if model.isLoading { MonchikLoader(large: true) } }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        RoutedStack {
            SupportTicketView()
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#endif
