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

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "calendar") }

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
            .tabItem { Label("Наборы", systemImage: "folder") }

            RewardsView()
                .tabItem { Label("Награды", systemImage: "trophy") }

            SpeakingHubView()
                .tabItem { Label("Речь", systemImage: "waveform") }

            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .task {
            // Раз в неделю база сама уезжает в файл — на случай, если
            // вспомнить про кнопку «Сохранить бэкап» не получится.
            BackupService(context: context).backupIfNeeded()
            SnapshotService.recordIfNeeded(context: context)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .plainText]
        ) { result in
            handleFileImport(result)
        }
        .onOpenURL { url in
            // Файл, присланный через «Поделиться» из Файлов или мессенджера.
            loadPlan { try ImportService(context: context).makePlan(from: try read(url)) }
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
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Импорт из файла", systemImage: "doc") { showFileImporter = true }
                Button("Вставить из буфера", systemImage: "doc.on.clipboard") {
                    showPasteImport = true
                }
                Divider()
                Button("Сохранить бэкап", systemImage: "arrow.down.doc") { exportBackup() }
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
        var lines = ["«\(result.deckName)»: \(result.addedNotes) слов, \(result.addedCards) карточек."]
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
