import SwiftUI
import SwiftData
import AJFMCore

/// Облачный бэкап на сервере Recap: включение, отправка снимка, восстановление.
struct CloudBackupView: View {
    @Environment(\.modelContext) private var context

    @State private var enabled = CloudBackupService.isEnabled
    @State private var list: CloudBackupList?
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?
    @State private var confirmErase = false
    @State private var pendingRestore: PendingCloudRestore?
    @State private var restored: RestoreService.Result?

    private var service: CloudBackupService { CloudBackupService(context: context) }
    private var entries: [CloudBackupEntry] { list?.backups ?? [] }

    var body: some View {
        List {
            if RecapBackend.isConfigured {
                switchSection
                if enabled { uploadSection }
                if list?.signedIn == false { signInHint }
                snapshotsSection
            } else {
                Section {
                    Text(tr("Сервер Recap не подключён в этой сборке — облачный бэкап недоступен. "
                                + "Бэкап файлом на вкладке «Наборы» работает всегда.",
                            "O servidor Recap não está ligado nesta versão — a cópia na nuvem não "
                                + "está disponível. O backup em ficheiro em «Baralhos» funciona sempre.",
                            "The Recap server isn't set up in this build, so cloud backup is off. "
                                + "File backups on the Decks tab always work."))
                        .foregroundStyle(Theme.muted)
                }
            }

            if let status {
                Section { Label(status, systemImage: "checkmark.circle").foregroundStyle(Theme.green) }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.orange)
                }
            }
        }
        .themedScreen()
        .navigationTitle(tr("Облачный бэкап", "Cópia na nuvem", "Cloud backup"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { MonchikLoader() } }
        .disabled(busy)
        .task { await refresh() }
        .refreshable { await refresh() }
        .confirmationDialog(
            tr("Удалить все копии с сервера?", "Apagar todas as cópias do servidor?",
               "Delete all copies from the server?"),
            isPresented: $confirmErase, titleVisibility: .visible
        ) {
            Button(tr("Удалить", "Apagar", "Delete"), role: .destructive) {
                perform { try await service.eraseAll() }
            }
            Button(CommonText.cancel, role: .cancel) {}
        }
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

    // MARK: - Секции

    private var switchSection: some View {
        Section {
            Toggle(tr("Хранить копии в облаке", "Guardar cópias na nuvem", "Keep copies in the cloud"),
                   isOn: $enabled)
                .accessibilityIdentifier("cloud.toggle")
                .onChange(of: enabled) { _, on in
                    CloudBackupService.isEnabled = on
                    // Включил — первая копия сразу, а не завтра.
                    if on { perform { try await service.upload() } }
                }
        } footer: {
            Text(tr("Раз в сутки сжатый снимок слов и прогресса уходит на сервер Recap и там "
                        + "шифруется. Хранятся последние \(list?.keep ?? 7). Никаких сторонних служб.",
                    "Uma vez por dia uma cópia comprimida das palavras e do progresso vai para o "
                        + "servidor Recap e é cifrada lá. Ficam as últimas \(list?.keep ?? 7). "
                        + "Sem serviços de terceiros.",
                    "Once a day a compressed snapshot of your words and progress goes to the Recap "
                        + "server and is encrypted there. The last \(list?.keep ?? 7) are kept. "
                        + "No third-party services."))
        }
    }

    private var uploadSection: some View {
        Section {
            Button(tr("Отправить снимок сейчас", "Enviar cópia agora", "Back up now"),
                   systemImage: "icloud.and.arrow.up") {
                perform { try await service.upload() }
            }
            .accessibilityIdentifier("cloud.upload")
            if let last = CloudBackupService.lastUpload {
                LabeledContent(tr("Последний", "Última", "Last"),
                               value: last.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var signInHint: some View {
        Section {
            Label {
                Text(tr("Войди через Apple в «Профиле» — тогда копии найдутся и на новом телефоне. "
                            + "Без входа они привязаны к этому.",
                        "Entra com a Apple no «Perfil» — assim as cópias aparecem também num "
                            + "telemóvel novo. Sem entrar, ficam ligadas a este.",
                        "Sign in with Apple in Profile so the copies show up on a new phone too. "
                            + "Without it they're tied to this one."))
                    .font(.app(.callout))
            } icon: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(Theme.orange)
            }
        }
    }

    private var snapshotsSection: some View {
        Section(tr("Снимки в облаке", "Cópias na nuvem", "Cloud snapshots")) {
            if entries.isEmpty {
                Text(tr("Пока ни одного.", "Ainda nenhuma.", "None yet."))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(entries) { entry in
                Button {
                    prepareRestore(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(Theme.ink)
                        Text(Counted.words(entry.noteCount) + " · " + entry.device + " · "
                             + ByteCountFormatter.string(
                                fromByteCount: Int64(entry.bytes), countStyle: .file))
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            if !entries.isEmpty {
                Button(tr("Удалить все копии", "Apagar todas as cópias", "Delete all copies"),
                       role: .destructive) {
                    confirmErase = true
                }
            }
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
        guard RecapBackend.isConfigured else { return }
        do {
            list = try await service.list()
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
