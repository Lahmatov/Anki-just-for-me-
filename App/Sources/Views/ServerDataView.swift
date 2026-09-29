import SwiftUI
import AJFMCore

/// «Что сервер знает обо мне» — право на доступ и перенос данных (GDPR,
/// ст. 15 и 20) прямо в приложении. Показываем как есть, без украшений,
/// и даём сохранить файлом.
struct ServerDataView: View {
    @State private var export: BackendAPI.ServerExport?
    @State private var file: URL?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if let error {
                Section { MascotSays(mood: .oops, text: error, size: 64) }
                    .listRowBackground(Color.clear)
            }
            if let export {
                content(export)
            } else if loading {
                Section { HStack { MonchikLoader(); Text(tr("Спрашиваю сервер…", "A perguntar ao servidor…",
                                                           "Asking the server…")) } }
            }
        }
        .themedScreen()
        .navigationTitle(tr("Мои данные на сервере", "Os meus dados no servidor", "My data on the server"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let file {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ export: BackendAPI.ServerExport) -> some View {
        Section {
            LabeledContent(tr("Код поддержки", "Código de suporte", "Support code")) {
                Text(export.supportCode).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            LabeledContent(tr("Устройство с", "Dispositivo desde", "Device since"),
                           value: date(export.device.registeredAt))
            LabeledContent(tr("Последний раз на связи", "Último contacto", "Last seen"),
                           value: date(export.device.lastSeenAt))
            LabeledContent(tr("Вход через Apple", "Sessão com a Apple", "Sign in with Apple"),
                           value: export.account.map { date($0.createdAt) }
                                ?? tr("нет", "não", "no"))
            LabeledContent(tr("Доступ", "Acesso", "Access"), value: planName(export.plan))
        } header: {
            Text(tr("Что хранится", "O que é guardado", "What is stored"))
        } footer: {
            Text(tr("Имени, почты, Apple ID и текстов запросов на сервере нет. Устройство, "
                        + "молчащее \(export.retentionDays.inactiveDevice) дней, забывается само, "
                        + "журнал расхода — через \(export.retentionDays.usageLog) дней.",
                    "O servidor não guarda nome, e-mail, Apple ID nem textos dos pedidos. Um "
                        + "dispositivo inativo \(export.retentionDays.inactiveDevice) dias é esquecido; "
                        + "o registo de consumo, ao fim de \(export.retentionDays.usageLog) dias.",
                    "The server keeps no name, e-mail, Apple ID or request text. A device silent for "
                        + "\(export.retentionDays.inactiveDevice) days is forgotten; the usage log after "
                        + "\(export.retentionDays.usageLog) days."))
        }

        Section(tr("Серии со словами", "Episódios com palavras", "Episodes with words")
                + " · \(export.episodes.count)") {
            if export.episodes.isEmpty {
                Text(tr("Пока нет", "Ainda nenhum", "None yet")).foregroundStyle(Theme.muted)
            }
            ForEach(Array(export.episodes.enumerated()), id: \.offset) { _, item in
                LabeledContent("TVmaze \(item.showId) · S\(item.season)E\(item.episode)",
                               value: date(item.at))
            }
        }

        Section {
            LabeledContent(tr("Запросов к ИИ", "Pedidos à IA", "AI requests"), value: "\(export.usage.count)")
            LabeledContent(tr("Токенов всего", "Tokens no total", "Tokens in total"),
                           value: export.totalTokens.formatted())
        } header: {
            Text(tr("Расход", "Consumo", "Usage"))
        } footer: {
            Text(tr("Только числа — сколько и когда. Что именно спрашивалось, сервер не хранит.",
                    "Só números — quanto e quando. O servidor não guarda o conteúdo.",
                    "Numbers only — how much and when. The server doesn't keep the content."))
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await RecapBackend.shared.exportData()
            export = result.export
            error = nil
            let url = FileManager.default.temporaryDirectory.appending(path: "recap-my-data.json")
            try result.json.write(to: url, options: [.atomic, .completeFileProtection])
            file = url
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func date(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func planName(_ plan: BackendAPI.PlanStatus) -> String {
        switch plan.kind {
        case .none: return tr("нет", "nenhum", "none")
        case .promo: return tr("промокод", "código promocional", "promo code")
                + (plan.active ? "" : tr(" (закончился)", " (terminou)", " (ended)"))
        case .subscription: return "Recap Plus" + (plan.active ? "" : tr(" (закончился)", " (terminou)", " (ended)"))
        }
    }
}
