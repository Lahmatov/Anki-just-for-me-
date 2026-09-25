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
            .navigationTitle(tr("Набор через Claude", "Baralho com o Claude", "Deck with Claude"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil { model = DeckRequestModel(context: context) }
            topicFocused = true
        }
        .interactiveDismissDisabled(model?.step == .working)
        .alert(
            tr("Не записалось", "Não foi guardado", "Couldn't save"),
            isPresented: Binding(
                get: { applyError != nil }, set: { if !$0 { applyError = nil } }),
            presenting: applyError
        ) { _ in
            Button(CommonText.gotIt) { applyError = nil }
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
                    tr("Friends 1x03, слова для собеседования…",
                       "Friends 1x03, palavras para uma entrevista…",
                       "Friends 1x03, words for a job interview…"),
                    text: $model.topic, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($topicFocused)
            } header: {
                Text(tr("Что нужно", "O que precisas", "What you need"))
            } footer: {
                Text(tr("Коротко, как в чате. Название серии, тема или ситуация — "
                            + "модель сама решит, какие слова взять.",
                        "Curto, como num chat. Nome do episódio, tema ou situação — "
                            + "o modelo decide que palavras escolher.",
                        "Short, like in a chat. An episode, a topic or a situation — "
                            + "the model decides which words to pick."))
            }

            Section {
                if let name = model.subtitlesName {
                    HStack {
                        Label(name, systemImage: "captions.bubble")
                            .lineLimit(1)
                        Spacer()
                        Button(tr("Убрать", "Remover", "Remove"), role: .destructive) {
                            model.removeSubtitles()
                        }
                            .font(.app(.callout))
                    }
                } else {
                    Button(tr("Приложить субтитры", "Anexar legendas", "Attach subtitles"),
                           systemImage: "captions.bubble") {
                        showSubtitlePicker = true
                    }
                }
            } footer: {
                Text(tr("С субтитрами примеры — настоящие реплики из серии. "
                            + "Без них — просто хорошие примеры, цитатами они не притворяются.",
                        "Com legendas, os exemplos são falas reais do episódio. Sem elas, "
                            + "são só bons exemplos — não se fazem passar por citações.",
                        "With subtitles, examples are real lines from the episode. Without "
                            + "them they're just good examples — they don't pose as quotes."))
            }

            Section {
                Stepper(
                    tr("Слов: ", "Palavras: ", "Words: ") + "\(model.wordCount)",
                    value: $model.wordCount,
                    in: DeckRequest.wordCountRange, step: 5)
                Picker(tr("Мой уровень", "O meu nível", "My level"), selection: $model.level) {
                    Text(tr("Не знаю", "Não sei", "Don't know")).tag(CEFRLevel?.none)
                    ForEach(CEFRLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(CEFRLevel?.some(level))
                    }
                }
            } footer: {
                Text(tr("Слова подбираются на ступень выше твоего уровня — "
                            + "уже не очевидные, но ещё часто встречающиеся.",
                        "As palavras ficam um degrau acima do teu nível — já não óbvias, "
                            + "mas ainda frequentes.",
                        "Words are picked one step above your level — no longer obvious, "
                            + "but still common."))
            }

            if !model.hasAPIKey {
                apiKeySection
            }

            Section {
                LabeledContent(
                    tr("Примерно", "Cerca de", "About"),
                    value: String(format: "$%.2f", model.estimatedCost))
                LabeledContent(
                    tr("В этом месяце", "Este mês", "This month"),
                    value: String(format: "$%.2f / $%.0f",
                                  model.usage.monthCost, model.usage.limit))
            } footer: {
                Text(tr("Слова, которые уже есть в базе, модель пропустит сама, "
                            + "а повторы превью покажет отдельно.",
                        "O modelo salta as palavras que já tens, e a pré-visualização "
                            + "mostra os duplicados à parte.",
                        "The model skips words you already have, and the preview "
                            + "shows duplicates separately."))
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
            SecureField(tr("Ключ API Anthropic", "Chave da API da Anthropic", "Anthropic API key"),
                        text: $apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: apiKey) { _, value in
                    Keychain.set(value.trimmingCharacters(in: .whitespaces),
                                 for: Keychain.claudeAPIKey)
                }
        } header: {
            Text(tr("Нужен ключ", "É precisa uma chave", "A key is needed"))
        } footer: {
            Text(tr("Один раз: console.anthropic.com → API Keys → Create Key. "
                        + "Ключ хранится в Keychain телефона и уходит только в Anthropic.",
                    "Uma vez: console.anthropic.com → API Keys → Create Key. "
                        + "A chave fica no Keychain do telemóvel e só vai para a Anthropic.",
                    "Once: console.anthropic.com → API Keys → Create Key. "
                        + "The key stays in the phone's Keychain and only goes to Anthropic."))
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
                    Text(tr("Подбираю слова…", "A escolher palavras…", "Picking words…"))
                } else {
                    Image(systemName: "sparkles")
                    Text(tr("Сделать набор", "Criar baralho", "Make the deck"))
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
            Text(Counted.words(result.addedNotes) + " · " + Counted.cards(result.addedCards))
                .foregroundStyle(.secondary)
            if let model, model.lastCost > 0 {
                Text(tr("Стоило ", "Custou ", "Cost ") + String(format: "$%.3f", model.lastCost))
                    .font(.app(.footnote))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(CommonText.done)
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
