import SwiftUI
import SwiftData
import AJFMCore

/// Облачный бэкап на сервере Recap: включение, отправка снимка, восстановление.
struct CloudBackupView: View {
    @Environment(\.modelContext) private var context
    @State private var model = CloudBackupViewModel()

    var body: some View {
        List {
            if model.isAvailable {
                switchSection
                if model.enabled { uploadSection }
                if model.showsSignInHint { signInHint }
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

            if let status = model.status {
                Section { Label(status, systemImage: "checkmark.circle").foregroundStyle(Theme.green) }
            }
            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.orange)
                }
            }
        }
        .themedScreen()
        .navigationTitle(tr("Облачный бэкап", "Cópia na nuvem", "Cloud backup"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if model.busy { MonchikLoader() } }
        .disabled(model.busy)
        .task { await model.refresh(in: context) }
        .refreshable { await model.refresh(in: context) }
        .confirmationDialog(
            tr("Удалить все копии с сервера?", "Apagar todas as cópias do servidor?",
               "Delete all copies from the server?"),
            isPresented: $model.confirmErase, titleVisibility: .visible
        ) {
            Button(tr("Удалить", "Apagar", "Delete"), role: .destructive, action: eraseAll)
            Button(CommonText.cancel, role: .cancel) {}
        }
        .alert(
            tr("Восстановить из облака?", "Restaurar da nuvem?", "Restore from the cloud?"),
            isPresented: $model.isRestorePending,
            presenting: model.pendingRestore
        ) { pending in
            Button(tr("Заменить всё", "Substituir tudo", "Replace everything"), role: .destructive) {
                model.restore(pending, in: context)
            }
            Button(CommonText.cancel, role: .cancel) {}
        } message: { pending in
            Text(Counted.words(pending.preview.notes) + ". "
                 + tr("Текущее содержимое будет заменено целиком.",
                      "O conteúdo atual será substituído por completo.",
                      "Everything currently in the app will be replaced."))
        }
        .alert(tr("Восстановлено", "Restaurado", "Restored"), isPresented: $model.isShowingRestored) {
            Button(CommonText.ok) {}
        } message: {
            if let restored = model.restored {
                Text(Counted.decks(restored.decks) + ", " + Counted.words(restored.notes))
            }
        }
    }

    // MARK: - Секции

    private var switchSection: some View {
        Section {
            Toggle(tr("Хранить копии в облаке", "Guardar cópias na nuvem", "Keep copies in the cloud"),
                   isOn: $model.enabled)
                .accessibilityIdentifier("cloud.toggle")
                .onChange(of: model.enabled) { _, on in model.enabledChanged(on, in: context) }
        } footer: {
            Text(tr("Раз в сутки сжатый снимок слов и прогресса уходит на сервер Recap и там "
                        + "шифруется. Хранятся последние \(model.keep). Никаких сторонних служб.",
                    "Uma vez por dia uma cópia comprimida das palavras e do progresso vai para o "
                        + "servidor Recap e é cifrada lá. Ficam as últimas \(model.keep). "
                        + "Sem serviços de terceiros.",
                    "Once a day a compressed snapshot of your words and progress goes to the Recap "
                        + "server and is encrypted there. The last \(model.keep) are kept. "
                        + "No third-party services."))
        }
    }

    private var uploadSection: some View {
        Section {
            Button(tr("Отправить снимок сейчас", "Enviar cópia agora", "Back up now"),
                   systemImage: "icloud.and.arrow.up", action: uploadNow)
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
            if model.entries.isEmpty {
                Text(tr("Пока ни одного.", "Ainda nenhuma.", "None yet."))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(model.entries) { entry in
                Button {
                    model.prepareRestore(entry, in: context)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(Theme.ink)
                        Text(Counted.words(entry.noteCount) + " · " + entry.device + " · "
                             + Int64(entry.bytes).formatted(.byteCount(style: .file)))
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            if !model.entries.isEmpty {
                Button(tr("Удалить все копии", "Apagar todas as cópias", "Delete all copies"),
                       role: .destructive) {
                    model.confirmErase = true
                }
            }
        }
    }

    // MARK: - Действия — в модели

    private func uploadNow() { model.uploadNow(in: context) }
    private func eraseAll() { model.eraseAll(in: context) }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        RoutedStack {
            CloudBackupView()
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#endif
