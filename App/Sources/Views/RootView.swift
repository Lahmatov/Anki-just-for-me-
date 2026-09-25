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
    @State private var pendingRestore: PendingRestore?
    @State private var restoreResult: RestoreService.Result?
    /// Заставка видна с первого кадра: иначе содержимое мелькнуло бы до неё.
    @State private var showIntro = true

    var body: some View {
        // Новый API вкладок: на iOS 26 таб-бар сам становится Liquid Glass
        // и прячется при прокрутке, освобождая место под содержимое.
        TabView {
            Tab("Сегодня", systemImage: "calendar") {
                TodayView()
            }

            Tab("Наборы", systemImage: "folder") {
                NavigationStack {
                    FolderContentsView(folder: nil, onExport: { exportedFile = $0 })
                        .navigationTitle("Наборы")
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

            Tab("Награды", systemImage: "trophy") {
                RewardsView()
            }

            Tab("Речь", systemImage: "waveform") {
                SpeakingHubView()
            }

            Tab("Настройки", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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
        .task {
            // Раз в неделю база сама уезжает в файл — на случай, если
            // вспомнить про кнопку «Сохранить бэкап» не получится.
            Log.info(.app, "Приложение запущено")
            BackupService(context: context).backupIfNeeded()
            SnapshotService.recordIfNeeded(context: context)
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
            "Восстановить из бэкапа?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { pending in
            Button("Заменить всё", role: .destructive) {
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
            Button("Отмена", role: .cancel) { pendingRestore = nil }
        } message: { pending in
            Text("В файле: наборов — \(pending.preview.decks), "
                 + "\(RussianPlural.words(pending.preview.notes)), из них выучено "
                 + "\(pending.preview.matureWords). Бэкап от "
                 + pending.preview.exportedAt.formatted(date: .abbreviated, time: .shortened)
                 + ". Текущее содержимое будет заменено целиком.")
        }
        .alert(
            "Восстановлено",
            isPresented: Binding(
                get: { restoreResult != nil },
                set: { if !$0 { restoreResult = nil } })
        ) {
            Button("Хорошо") { restoreResult = nil }
        } message: {
            if let restoreResult {
                Text("Наборов: \(restoreResult.decks), слов: \(restoreResult.notes), "
                     + "карточек: \(restoreResult.cards) — вместе с прогрессом.")
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
        .sheet(item: $onboarding) { plan in
            OnboardingView(plan: plan)
        }
        .sheet(isPresented: $showPasteImport) {
            PasteImportView { text in
                loadPlan { try ImportService(context: context).makePlan(from: text) }
            }
        }
        .sheet(item: $pendingImport) { pending in
            ImportPreviewView(plan: pending.plan) { includeDuplicates in
                applyPlan(pending.plan, includeDuplicates: includeDuplicates)
            }
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(url: file.url)
        }
        .alert(
            "Не получилось",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }),
            presenting: importError
        ) { _ in
            Button("Понятно") { importError = nil }
        } message: { error in
            Text(error.message)
        }
        .alert("Запрос скопирован", isPresented: $promptCopied) {
            Button("Понятно") { promptCopied = false }
        } message: {
            Text("Вставь его мне в чат, подставив название серии и слова. "
                 + "В ответ придёт готовый файл набора.")
        }
        .alert(
            "Готово",
            isPresented: Binding(get: { lastResult != nil }, set: { if !$0 { lastResult = nil } })
        ) {
            Button("Хорошо") { lastResult = nil }
        } message: {
            if let lastResult {
                Text(summary(of: lastResult))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Главный способ получить слова — отдельной кнопкой, а не в меню.
        ToolbarItem(placement: .topBarTrailing) {
            Button("Набор через Claude", systemImage: "sparkles") {
                showDeckRequest = true
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Новое слово", systemImage: "plus.circle") { showQuickAdd = true }
                Divider()
                Button("Импорт из файла", systemImage: "doc") { showFileImporter = true }
                Button("Вставить из буфера", systemImage: "doc.on.clipboard") {
                    showPasteImport = true
                }
                Divider()
                Button("Сохранить бэкап", systemImage: "arrow.down.doc") { exportBackup() }
                Button("Восстановить из бэкапа", systemImage: "arrow.up.doc") {
                    showRestoreImporter = true
                }
                Divider()
                Button("Запрос для Claude", systemImage: "doc.on.clipboard.fill") {
                    UIPasteboard.general.string = PromptTemplates.newDeck(
                        source: "название серии", words: [])
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
        var lines = ["«\(result.deckName)»: \(RussianPlural.words(result.addedNotes)), "
            + "\(RussianPlural.cards(result.addedCards))."]
        if result.skippedDuplicates > 0 {
            lines.append("Пропущено дублей: \(result.skippedDuplicates).")
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
    /// Знакомство показывается один раз, а потом — только по своей воле
    /// из настроек.
    @MainActor
    func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.onboardingDone) else {
            return
        }
        onboarding = OnboardingPlanBuilder.make(context: context)
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
