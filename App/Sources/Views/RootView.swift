import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import AJFMCore

struct RootView: View {
    @Environment(\.modelContext) private var context

    @State private var pendingImport: PendingImport?
    @State private var importError: ImportError?
    @State private var lastResult: ImportResult?
    @State private var showFileImporter = false
    @State private var showPasteImport = false
    @State private var exportedFile: ExportedFile?
    @State private var promptCopied = false
    @State private var showRestoreImporter = false
    @State private var showQuickAdd = false
    @State private var showDeckRequest = false
    @State private var onboarding: OnboardingPlan?
    /// Сколько раз закрывалось знакомство — сигнал «Сегодня» перечитать базу.
    @State private var onboardingFinished = 0
    @State private var pendingRestore: PendingRestore?
    @State private var restoreResult: RestoreService.Result?
    /// Заставка видна с первого кадра: иначе содержимое мелькнуло бы до неё.
    @State private var showIntro = !UITesting.isActive
    /// Вкладка хранится снаружи пересоздаваемого дерева: смена шрифта
    /// перестраивает экраны, но не выкидывает из настроек на «Сегодня».
    @State private var tab: AppTab = .today
    @State private var keyboard = KeyboardObserver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var tabBarVisibility: TabBarVisibility { .shared }
    @AppStorage(SettingsKey.fontStyle) private var fontStyle = AppFont.nunito.rawValue
    /// Пустая строка — язык не выбран явно, действует системный.
    @AppStorage(SettingsKey.appLanguage) private var language = ""
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        // Свои вкладки вместо системного TabView — стекло то же, что в iOS 26,
        // но живёт только открытая вкладка. Когда жили все пять сразу, каждое
        // сохранение в базе перерисовывало и скрытые — с полными выборками
        // карточек и повторов, — и телефон грелся. Цена — при переключении
        // вкладка открывается с начала.
        // Панель — под содержимым, а не поверх него. Поверх (overlay или
        // safeAreaInset снаружи NavigationStack) экраны не всегда получали
        // нижний отступ, и последние кнопки уезжали под панель.
        VStack(spacing: 0) {
            // Вкладки сменяются растворением с лёгким подъёмом, а не
            // подменой кадра: мгновенная подмена читалась как рывок.
            ZStack {
                Group {
                    switch tab {
                    case .today: TodayView(refreshToken: onboardingFinished)
                    case .decks: decksTab
                    case .shows: ShowsView()
                    case .settings: SettingsView()
                    }
                }
                .id(tab)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                          removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.tabSwitch, value: tab)

            // Пока открыта клавиатура, панель прячется: иначе она висела бы
            // над клавиатурой и отъедала место у поля ввода.
            if !keyboard.isVisible, !tabBarVisibility.hiddenBySession {
                AppTabBar(selection: $tab)
                    .background(Theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        // Смена шрифта или языка перестраивает экраны целиком: тексты берут
        // и то и другое в момент отрисовки.
        .id(fontStyle + language)
        .overlay {
            if let moment = Celebrations.shared.current {
                CelebrationOverlay(title: moment.title, subtitle: moment.subtitle) {
                    Celebrations.shared.dismiss()
                }
                .id(moment.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.app, value: Celebrations.shared.current)
        .overlay {
            if showIntro {
                LaunchIntroView {
                    showIntro = false
                    // Знакомство — после заставки, а не поверх неё.
                    showOnboardingIfNeeded()
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            // В UI-тестах заставки нет, а знакомство запускается после неё.
            if UITesting.wantsOnboarding { showOnboardingIfNeeded() }
        }
        .task {
            // Раз в неделю база сама уезжает в файл — на случай, если
            // вспомнить про кнопку «Сохранить бэкап» не получится.
            Log.info(.app, "Приложение запущено")
            BackupService(context: context).backupIfNeeded()
            SnapshotService.recordIfNeeded(context: context)
            RecapAccount.shared.start()
            await NotificationService.reschedule(context: context)
            WidgetBridge.update(context: context)
            // Облако — последним: сеть может думать долго, а остальное локально.
            await CloudBackupService(context: context).uploadIfNeeded()
        }
        // Уходя в фон, перестраиваем напоминания: сегодня уже занимались —
        // сегодняшнее снимается, а данные виджета обновляются.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            WidgetBridge.update(context: context)
            Task { await NotificationService.reschedule(context: context) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .plainText]
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let (backup, preview) = try RestoreService(context: context)
                        .preview(from: try read(url))
                    pendingRestore = PendingRestore(backup: backup, preview: preview)
                } catch {
                    importError = ImportError(message: error.localizedDescription)
                }
            case .failure(let error):
                importError = ImportError(message: error.localizedDescription)
            }
        }
        .alert(
            tr("Восстановить из бэкапа?", "Restaurar a cópia de segurança?",
               "Restore from backup?"),
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { pending in
            Button(tr("Заменить всё", "Substituir tudo", "Replace everything"),
                   role: .destructive) {
                pendingRestore = nil
                // Явный тип: у сервиса есть собственный Result.
                let outcome: Swift.Result<RestoreService.Result, Error> = Result {
                    try RestoreService(context: context).restore(pending.backup)
                }
                // Оба исхода показываем следующим циклом обновления:
                // оповещение, поднятое в том же проходе, что и закрытие
                // предыдущего, теряется.
                Task { @MainActor in
                    switch outcome {
                    case .success(let value): restoreResult = value
                    case .failure(let error):
                        importError = ImportError(message: error.localizedDescription)
                    }
                }
            }
            Button(CommonText.cancel, role: .cancel) { pendingRestore = nil }
        } message: { pending in
            let date = pending.preview.exportedAt.formatted(date: .abbreviated, time: .shortened)
            let words = Counted.words(pending.preview.notes)
            let decks = Counted.decks(pending.preview.decks)
            let mature = pending.preview.matureWords
            Text(tr(
                "В файле \(decks), \(words), из них выучено \(mature). Бэкап от \(date). "
                    + "Текущее содержимое будет заменено целиком.",
                "O ficheiro tem \(decks), \(words), das quais \(mature) aprendidas. Cópia de "
                    + "\(date). O conteúdo atual será substituído por completo.",
                "The file has \(decks), \(words), \(mature) of them learned. Backup from "
                    + "\(date). Everything currently in the app will be replaced."))
        }
        .alert(
            tr("Восстановлено", "Restaurado", "Restored"),
            isPresented: Binding(
                get: { restoreResult != nil },
                set: { if !$0 { restoreResult = nil } })
        ) {
            Button(CommonText.ok) { restoreResult = nil }
        } message: {
            if let restoreResult {
                Text(Counted.decks(restoreResult.decks) + ", "
                     + Counted.words(restoreResult.notes) + ", "
                     + Counted.cards(restoreResult.cards)
                     + tr(" — вместе с прогрессом.", " — com o progresso.",
                          " — progress included."))
            }
        }
        .onOpenURL { url in
            // Файл, присланный через «Поделиться» из Файлов или мессенджера.
            loadPlan { try ImportService(context: context).makePlan(from: try read(url)) }
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView()
        }
        .sheet(isPresented: $showDeckRequest) {
            DeckRequestView()
        }
        // На весь экран, а не листом: знакомство — первое, что видно
        // в приложении, и случайный свайп вниз не должен его сбрасывать.
        .fullScreenCover(item: $onboarding, onDismiss: { onboardingFinished += 1 }) { plan in
            OnboardingView(plan: plan)
        }
        .sheet(isPresented: $showPasteImport) {
            PasteImportView { text in
                loadPlan { try ImportService(context: context).makePlan(from: text) }
            }
        }
        .sheet(item: $pendingImport) { pending in
            ImportPreviewView(plan: pending.plan) { edited, includeDuplicates in
                applyPlan(edited, includeDuplicates: includeDuplicates)
            }
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(url: file.url)
        }
        .alert(
            CommonText.failedTitle,
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }),
            presenting: importError
        ) { _ in
            Button(CommonText.gotIt) { importError = nil }
        } message: { error in
            Text(error.message)
        }
        .alert(tr("Запрос скопирован", "Pedido copiado", "Request copied"),
               isPresented: $promptCopied) {
            Button(CommonText.gotIt) { promptCopied = false }
        } message: {
            Text(tr("Вставь его в чат с Claude, подставив название серии и слова. "
                        + "В ответ придёт готовый файл набора.",
                    "Cola-o no chat com o Claude, com o nome do episódio e as palavras. "
                        + "A resposta traz o ficheiro do baralho pronto.",
                    "Paste it into a chat with Claude, filling in the episode and the words. "
                        + "The reply will be a ready deck file."))
        }
        .alert(
            CommonText.done,
            isPresented: Binding(get: { lastResult != nil }, set: { if !$0 { lastResult = nil } })
        ) {
            Button(CommonText.ok) { lastResult = nil }
        } message: {
            if let lastResult {
                Text(summary(of: lastResult))
            }
        }
        // В самом конце, чтобы доставалось и листам: шрифт по умолчанию для
        // текстов без явного стиля, даты и числа — по языку интерфейса.
        .font(.app(.body))
        .environment(\.locale, Locale(identifier: Loc.language.localeIdentifier))
    }

    private var decksTab: some View {
        NavigationStack {
            FolderContentsView(folder: nil, onExport: { exportedFile = $0 })
                .tabRootTitle(AppTab.decks.title)
                .toolbar { toolbar }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            SearchView()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Главный способ получить слова — отдельной кнопкой, а не в меню.
        ToolbarItem(placement: .topBarTrailing) {
            Button(tr("Набор через Claude", "Baralho com o Claude", "Deck with Claude"),
                   systemImage: "sparkles") {
                showDeckRequest = true
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(tr("Новое слово", "Nova palavra", "New word"), systemImage: "plus.circle") {
                    showQuickAdd = true
                }
                Divider()
                Button(tr("Импорт из файла", "Importar de ficheiro", "Import from file"),
                       systemImage: "doc") { showFileImporter = true }
                Button(tr("Вставить из буфера", "Colar da área de transferência", "Paste from clipboard"),
                       systemImage: "doc.on.clipboard") {
                    showPasteImport = true
                }
                Divider()
                Button(tr("Сохранить бэкап", "Guardar cópia de segurança", "Save backup"),
                       systemImage: "arrow.down.doc") { exportBackup() }
                Button(tr("Восстановить из бэкапа", "Restaurar cópia de segurança", "Restore from backup"),
                       systemImage: "arrow.up.doc") {
                    showRestoreImporter = true
                }
                Divider()
                Button(tr("Запрос для чата с Claude", "Pedido para o chat com o Claude",
                          "Request for a Claude chat"),
                       systemImage: "doc.on.clipboard.fill") {
                    UIPasteboard.general.string = PromptTemplates.newDeck(
                        source: tr("название серии", "nome do episódio", "episode name"),
                        words: [])
                    promptCopied = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Импорт

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            loadPlan { try ImportService(context: context).makePlan(from: try read(url)) }
        case .failure(let error):
            importError = ImportError(message: error.localizedDescription)
        }
    }

    /// Файл из «Файлов» лежит вне песочницы — без этого чтение молча вернёт отказ.
    private func read(_ url: URL) throws -> Data {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func loadPlan(_ build: () throws -> ImportPlan) {
        do {
            pendingImport = PendingImport(plan: try build())
        } catch {
            importError = ImportError(message: message(for: error))
        }
    }

    private func applyPlan(_ plan: ImportPlan, includeDuplicates: Bool) {
        pendingImport = nil
        do {
            lastResult = try ImportService(context: context)
                .apply(plan, includeDuplicates: includeDuplicates)
        } catch {
            importError = ImportError(message: error.localizedDescription)
        }
    }

    private func message(for error: Error) -> String {
        (error as? DeckParseError)?.errorDescription ?? error.localizedDescription
    }

    private func summary(of result: ImportResult) -> String {
        var lines = ["«\(result.deckName)»: \(Counted.words(result.addedNotes)), "
            + "\(Counted.cards(result.addedCards))."]
        if result.skippedDuplicates > 0 {
            lines.append(tr("Пропущено дублей: ", "Duplicados ignorados: ", "Duplicates skipped: ")
                + "\(result.skippedDuplicates).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Экспорт

    private func exportBackup() {
        do {
            exportedFile = ExportedFile(url: try ExportService(context: context).writeBackupFile())
        } catch {
            importError = ImportError(message: error.localizedDescription)
        }
    }
}

extension RootView {
    /// Знакомство показывается при первом запуске и ещё раз, когда выходит
    /// новая его версия; в остальное время — только по своей воле из настроек.
    @MainActor
    func showOnboardingIfNeeded() {
        guard !UITesting.isActive || UITesting.wantsOnboarding else { return }
        let defaults = UserDefaults.standard
        let seen = OnboardingPlan.seenVersion(
            stored: defaults.integer(forKey: SettingsKey.onboardingVersion),
            legacyDone: defaults.bool(forKey: SettingsKey.onboardingDone))
        guard OnboardingPlan.shouldShow(seenVersion: seen) else { return }
        let plan = OnboardingPlanBuilder.make(context: context)
        // Следующим циклом: лист, поднятый в том же проходе, где уходит
        // заставка, SwiftUI иногда теряет — и знакомство не появлялось.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            onboarding = plan
        }
    }
}

enum AppTab: Hashable, CaseIterable {
    // Награды — не вкладка, а экран с «Сегодня»: четыре вкладки просторнее пяти.
    case today, decks, shows, settings

    var title: String {
        switch self {
        case .today: return tr("Сегодня", "Hoje", "Today")
        case .decks: return tr("Наборы", "Baralhos", "Decks")
        case .shows: return tr("Сериалы", "Séries", "Shows")
        case .settings: return tr("Настройки", "Definições", "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .decks: return "rectangle.stack.fill"
        case .shows: return "tv.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct PendingRestore: Identifiable {
    let id = UUID()
    let backup: BackupFile
    let preview: RestoreService.Preview
}

struct PendingImport: Identifiable {
    let id = UUID()
    let plan: ImportPlan
}

struct ImportError: Identifiable {
    let id = UUID()
    let message: String
}

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}
