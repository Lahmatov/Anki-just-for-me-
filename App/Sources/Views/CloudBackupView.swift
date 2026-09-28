import SwiftUI
import SwiftData
import AJFMCore

/// Облачный бэкап в Neon: подключение, отправка снимка, восстановление.
struct CloudBackupView: View {
    @Environment(\.modelContext) private var context

    @State private var connectionText = ""
    @State private var entries: [CloudBackupEntry] = []
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?
    @State private var pendingRestore: PendingCloudRestore?
    @State private var restored: RestoreService.Result?

    private var service: CloudBackupService { CloudBackupService(context: context) }

    var body: some View {
        List {
            connectionSection

            if CloudBackupService.isConfigured {
                Section {
                    Button(tr("Отправить снимок сейчас", "Enviar cópia agora", "Back up now"),
                           systemImage: "icloud.and.arrow.up") {
                        perform { try await service.upload() }
                    }
                    if let last = CloudBackupService.lastUpload {
                        LabeledContent(tr("Последний", "Última", "Last"),
                                       value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                } footer: {
                    Text(tr("Раз в сутки снимок уходит сам при запуске приложения. "
                                + "Хранятся последние \(CloudBackupSQL.keep).",
                            "Uma vez por dia a cópia vai sozinha quando abres a aplicação. "
                                + "Ficam guardadas as últimas \(CloudBackupSQL.keep).",
                            "Once a day a snapshot goes up by itself when you open the app. "
                                + "The last \(CloudBackupSQL.keep) are kept."))
                }

                Section(tr("Снимки в облаке", "Cópias na nuvem", "Cloud snapshots")) {
                    if entries.isEmpty {
                        Text(tr("Пока ни одного.", "Ainda nenhuma.", "None yet."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        Button {
                            prepareRestore(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(Retro.ink)
                                Text(Counted.words(entry.noteCount) + " · " + entry.device + " · "
                                     + ByteCountFormatter.string(
                                        fromByteCount: Int64(entry.bytes), countStyle: .file))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let status {
                Section { Label(status, systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
        }
        .retroScreen()
        .navigationTitle(tr("Облако Neon", "Nuvem Neon", "Neon cloud"))
        .overlay { if busy { ProgressView() } }
        .disabled(busy)
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert(
            tr("Восстановить из облака?", "Restaurar da nuvem?", "Restore from the cloud?"),
            isPresented: Binding(
                get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { pending in
            Button(tr("Заменить всё", "Substituir tudo", "Replace everything"),
                   role: .destructive) {
                restore(pending)
            }
            Button(CommonText.cancel, role: .cancel) { pendingRestore = nil }
        } message: { pending in
            Text(Counted.words(pending.preview.notes) + ". "
                 + tr("Текущее содержимое будет заменено целиком.",
                      "O conteúdo atual será substituído por completo.",
                      "Everything currently in the app will be replaced."))
        }
        .alert(
            tr("Восстановлено", "Restaurado", "Restored"),
            isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })
        ) {
            Button(CommonText.ok) { restored = nil }
        } message: {
            if let restored {
                Text(Counted.decks(restored.decks) + ", " + Counted.words(restored.notes))
            }
        }
    }

    // MARK: - Подключение

    private var connectionSection: some View {
        Section {
            if let connection = CloudBackupService.connection {
                LabeledContent(tr("База", "Base de dados", "Database"), value: connection.redacted)
                Button(tr("Отключить", "Desligar", "Disconnect"), role: .destructive) {
                    Keychain.set("", for: Keychain.neonConnection)
                    entries = []
                    status = nil
                }
            } else {
                SecureField("postgresql://…neon.tech/neondb", text: $connectionText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(tr("Подключить", "Ligar", "Connect"), systemImage: "link") {
                    connect()
                }
                .disabled(connectionText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Neon")
        } footer: {
            Text(tr("Бесплатно: neon.tech → создать проект → Connect → скопировать "
                        + "Connection string. Строка хранится в Keychain телефона.",
                    "Grátis: neon.tech → criar projeto → Connect → copiar a "
                        + "Connection string. A ligação fica no Keychain do telemóvel.",
                    "Free: neon.tech → create a project → Connect → copy the "
                        + "Connection string. It's kept in the phone's Keychain."))
        }
    }

    private func connect() {
        do {
            let connection = try NeonConnection(connectionString: connectionText)
            perform {
                try await service.connect(connection)
                connectionText = ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Действия

    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true
        error = nil
        status = nil
        Task {
            do {
                try await action()
                status = tr("Готово", "Feito", "Done")
                await refresh()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func refresh() async {
        guard CloudBackupService.isConfigured else { return }
        do {
            entries = try await service.list()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func prepareRestore(_ entry: CloudBackupEntry) {
        busy = true
        error = nil
        Task {
            do {
                let data = try await service.download(entry)
                let (backup, preview) = try RestoreService(context: context).preview(from: data)
                pendingRestore = PendingCloudRestore(backup: backup, preview: preview)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func restore(_ pending: PendingCloudRestore) {
        pendingRestore = nil
        do {
            let result = try RestoreService(context: context).restore(pending.backup)
            // Показ итога — следующим циклом: алерт, поднятый в том же проходе,
            // что и закрытие предыдущего, теряется.
            Task { @MainActor in restored = result }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PendingCloudRestore: Identifiable {
    let id = UUID()
    let backup: BackupFile
    let preview: RestoreService.Preview
}
