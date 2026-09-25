import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AJFMCore

/// Набор по короткому запросу: написал «Friends 1x03» — получил слова.
///
/// Результат идёт через то же превью, что и импорт файла: модель может
/// ошибиться, и увидеть слова до записи в базу обязательно.
struct DeckRequestView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var model: DeckRequestModel?
    @State private var plan: PendingImport?
    @State private var result: ImportResult?
    @State private var showSubtitlePicker = false
    @State private var apiKey = ""
    @State private var applyError: String?
    @FocusState private var topicFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    doneView(result)
                } else if let model {
                    form(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Набор через Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil { model = DeckRequestModel(context: context) }
            topicFocused = true
        }
        .interactiveDismissDisabled(model?.step == .working)
        .alert(
            "Не записалось",
            isPresented: Binding(
                get: { applyError != nil }, set: { if !$0 { applyError = nil } }),
            presenting: applyError
        ) { _ in
            Button("Понятно") { applyError = nil }
        } message: { message in
            Text(message)
        }
        .sheet(item: $plan) { pending in
            ImportPreviewView(plan: pending.plan) { includeDuplicates in
                apply(pending.plan, includeDuplicates: includeDuplicates)
            }
        }
    }

    // MARK: - Форма

    @ViewBuilder
    private func form(_ model: DeckRequestModel) -> some View {
        @Bindable var model = model
        Form {
            Section {
                TextField(
                    "Friends 1x03, слова для собеседования…",
                    text: $model.topic, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($topicFocused)
            } header: {
                Text("Что нужно")
            } footer: {
                Text("Коротко, как в чате. Название серии, тема или ситуация — "
                     + "модель сама решит, какие слова взять.")
            }

            Section {
                if let name = model.subtitlesName {
                    HStack {
                        Label(name, systemImage: "captions.bubble")
                            .lineLimit(1)
                        Spacer()
                        Button("Убрать", role: .destructive) { model.removeSubtitles() }
                            .font(.app(.callout))
                    }
                } else {
                    Button("Приложить субтитры", systemImage: "captions.bubble") {
                        showSubtitlePicker = true
                    }
                }
            } footer: {
                Text("С субтитрами примеры — настоящие реплики из серии. "
                     + "Без них — просто хорошие примеры, цитатами они не притворяются.")
            }

            Section {
                Stepper(
                    "Слов: \(model.wordCount)", value: $model.wordCount,
                    in: DeckRequest.wordCountRange, step: 5)
                Picker("Мой уровень", selection: $model.level) {
                    Text("Не знаю").tag(CEFRLevel?.none)
                    ForEach(CEFRLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(CEFRLevel?.some(level))
                    }
                }
            } footer: {
                Text("Слова подбираются на ступень выше твоего уровня — "
                     + "уже не очевидные, но ещё часто встречающиеся.")
            }

            if !model.hasAPIKey {
                apiKeySection
            }

            Section {
                LabeledContent(
                    "Примерно", value: String(format: "$%.2f", model.estimatedCost))
                LabeledContent(
                    "В этом месяце",
                    value: String(format: "$%.2f из $%.0f",
                                  model.usage.monthCost, model.usage.limit))
            } footer: {
                Text("Слова, которые уже есть в базе, модель пропустит сама, "
                     + "а повторы превью покажет отдельно.")
            }

            if case .failed(let message) = model.step {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.app(.callout))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            submitButton(model)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .fileImporter(
            isPresented: $showSubtitlePicker,
            allowedContentTypes: [.plainText, .text, .data]
        ) { outcome in
            guard case .success(let url) = outcome else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                model.loadSubtitles(from: data, name: url.lastPathComponent)
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("Ключ API Anthropic", text: $apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: apiKey) { _, value in
                    Keychain.set(value.trimmingCharacters(in: .whitespaces),
                                 for: Keychain.claudeAPIKey)
                }
        } header: {
            Text("Нужен ключ")
        } footer: {
            Text("Один раз: console.anthropic.com → API Keys → Create Key. "
                 + "Ключ хранится в Keychain телефона и уходит только в Anthropic.")
        }
    }

    @ViewBuilder
    private func submitButton(_ model: DeckRequestModel) -> some View {
        Button {
            Haptics.tap()
            topicFocused = false
            Task {
                if let generated = await model.generate() {
                    Haptics.success()
                    plan = PendingImport(plan: generated)
                } else {
                    Haptics.failure()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if model.step == .working {
                    ProgressView()
                    Text("Подбираю слова…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Сделать набор")
                }
            }
            .font(.app(.headline))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!model.canSubmit || (!model.hasAPIKey && apiKey.isEmpty))
    }

    // MARK: - Итог

    private func doneView(_ result: ImportResult) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: result.addedNotes)
            Text(result.deckName)
                .font(.app(.title2, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(RussianPlural.words(result.addedNotes) + " · "
                 + RussianPlural.cards(result.addedCards))
                .foregroundStyle(.secondary)
            if let model, model.lastCost > 0 {
                Text(String(format: "Стоило $%.3f", model.lastCost))
                    .font(.app(.footnote))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Готово")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private func apply(_ plan: ImportPlan, includeDuplicates: Bool) {
        self.plan = nil
        do {
            result = try ImportService(context: context)
                .apply(plan, includeDuplicates: includeDuplicates)
        } catch {
            Log.failure(.importing, "Набор от Claude не записался", error)
            applyError = error.localizedDescription
        }
    }
}
