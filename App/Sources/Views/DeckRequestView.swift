import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import PhotosUI
import AJFMCore

/// Набор по короткому запросу: написал «Friends 1x03» — получил слова.
///
/// Результат идёт через то же превью, что и импорт файла: модель может
/// ошибиться, и увидеть слова до записи в базу обязательно.
struct DeckRequestView: View {
    /// Запрос, подставленный заранее, — например, с экрана серии.
    var initialTopic: String = ""
    /// Серия с экрана «Сериалы»: сервер получит её номер напрямую.
    var episode: EpisodeContext?
    /// Фильм из поиска: вместо поля запроса — его карточка.
    var movie: Movie?
    /// Карточки из урока: вместо темы — выжимка занятия (P-68).
    var lessonMode = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var model: DeckRequestModel?
    @State private var plan: PendingImport?
    @State private var result: ImportResult?
    @State private var showSubtitlePicker = false
    @State private var showPlacementTest = false
    @State private var apiKey = ""
    @State private var applyError: String?
    @State private var pendingAI: (() -> Void)?
    @FocusState private var topicFocused: Bool
    // Урок с фото и из PDF (P-69).
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPDFPicker = false
    @State private var pickingPDF = false
    @State private var scanning = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    doneView(result)
                } else if let model {
                    form(model)
                } else {
                    MonchikLoader(large: true)
                }
            }
            .animation(.app, value: result != nil)
            .navigationTitle(lessonMode
                             ? tr("Карточки из урока", "Cartões da aula", "Cards from a lesson")
                             : tr("Набор через Claude", "Baralho com o Claude", "Deck with Claude"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil {
                let created = DeckRequestModel(context: context)
                if !initialTopic.isEmpty { created.topic = initialTopic }
                created.episode = episode
                if lessonMode { created.lesson = "" }
                if let movie {
                    created.movie = movie
                    created.topic = movie.deckTopic
                }
                model = created
            }
            // У фильма поля запроса нет — и клавиатура выскакивать не должна.
            topicFocused = movie == nil && !lessonMode
        }
        .interactiveDismissDisabled(model?.step == .working || model?.step == .interrupted)
        // Вернулись в приложение — продолжаем оборванный запрос с тем же номером.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let model, model.step == .interrupted { run(model) }
        }
        .aiConsentAlert(pending: $pendingAI)
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
            ImportPreviewView(plan: pending.plan) { edited, includeDuplicates in
                apply(edited, includeDuplicates: includeDuplicates)
            }
        }
    }

    // MARK: - Урок (P-68)

    @ViewBuilder
    private func lessonSection(_ model: DeckRequestModel) -> some View {
        @Bindable var model = model
        Section {
            TextField(tr("Название (необязательно): «Урок 5»",
                         "Nome (opcional): «Aula 5»",
                         "Title (optional): “Lesson 5”"),
                      text: $model.topic)
            TextEditor(text: Binding(get: { model.lesson ?? "" }, set: { model.lesson = $0 }))
                .frame(minHeight: 180)
                .font(.app(.body))
                .overlay(alignment: .topLeading) {
                    if (model.lesson ?? "").isEmpty {
                        Text(tr("Вставь выжимку урока: слова с доски, конспект, правило…",
                                "Cola o resumo da aula: palavras do quadro, apontamentos, uma regra…",
                                "Paste the lesson summary: words from the board, notes, a rule…"))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("lesson.text")
            if UIPasteboard.general.hasStrings {
                Button(tr("Вставить из буфера", "Colar", "Paste"), systemImage: "doc.on.clipboard") {
                    model.lesson = (model.lesson ?? "") + (UIPasteboard.general.string ?? "")
                }
            }
            scanButtons(model)
        } header: {
            Text(tr("Что было на уроке", "O que se deu na aula", "What the lesson covered"))
        } footer: {
            Text(tr("Слова и фразы станут карточками с переводом, правила — карточками "
                        + "«конструкция → объяснение» с примером. Наборы ложатся в папку «Уроки».",
                    "As palavras e expressões viram cartões com tradução, as regras — cartões "
                        + "«construção → explicação» com exemplo. Os baralhos vão para a pasta «Aulas».",
                    "Words and phrases become cards with a translation, rules become "
                        + "“pattern → explanation” cards with an example. Decks go into Lessons."))
        }
        Section {
            Button(tr("Скопировать промпт для своего чата", "Copiar o prompt para o meu chat",
                      "Copy the prompt for my own chat"), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = model.request.chatPrompt
                Haptics.success()
            }
            .disabled(!model.request.hasLesson)
        } footer: {
            Text(tr("Без ключа и подписки: вставь промпт в Claude или ChatGPT, скопируй ответ "
                        + "и открой «Наборы» → меню «…» → «Вставить из буфера».",
                    "Sem chave nem subscrição: cola o prompt no Claude ou no ChatGPT, copia a "
                        + "resposta e abre «Baralhos» → menu «…» → «Colar da área de transferência».",
                    "No key or subscription: paste the prompt into Claude or ChatGPT, copy the "
                        + "answer, then open Decks → the “…” menu → Paste from clipboard."))
        }
    }

    /// Фото страницы, снимки из галереи и PDF — текст распознаётся на телефоне
    /// и дописывается в поле, где его можно поправить до отправки.
    @ViewBuilder
    private func scanButtons(_ model: DeckRequestModel) -> some View {
        if scanning {
            HStack(spacing: 10) {
                MonchikLoader()
                Text(tr("Читаю страницу…", "A ler a página…", "Reading the page…"))
                    .foregroundStyle(Theme.muted)
            }
        } else {
            if DocumentCameraView.isAvailable {
                Button(tr("Сфотографировать страницу", "Fotografar a página", "Scan a page"),
                       systemImage: "camera.viewfinder") { showCamera = true }
                    .accessibilityIdentifier("lesson.camera")
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                Label(tr("Из фото", "Das fotos", "From photos"), systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("lesson.photos")
            Button(tr("Из PDF", "De um PDF", "From a PDF"), systemImage: "doc.richtext") {
                pickingPDF = true
                showPDFPicker = true
            }
            .accessibilityIdentifier("lesson.pdf")
        }
        if let scanError {
            Label(scanError, systemImage: "exclamationmark.triangle")
                .font(.app(.callout))
                .foregroundStyle(Theme.orange)
        }
    }

    private func appendScan(_ model: DeckRequestModel, _ work: @escaping () async throws -> String) {
        scanning = true
        scanError = nil
        Task {
            defer { scanning = false }
            do {
                let text = try await work()
                let current = (model.lesson ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                model.lesson = current.isEmpty ? text : current + "\n\n" + text
                Haptics.success()
            } catch {
                Log.failure(.importing, "Текст урока не распознался", error)
                scanError = error.localizedDescription
            }
        }
    }

    // MARK: - Форма

    @ViewBuilder
    private func form(_ model: DeckRequestModel) -> some View {
        @Bindable var model = model
        Form {
            if let movie = model.movie {
                Section {
                    HStack(spacing: 14) {
                        if let url = movie.posterURL.flatMap({ URL(string: $0) }) {
                            CoverImage(url: url, width: 54)
                        } else {
                            IconBadge(systemName: "film", color: Theme.purple, size: 54)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(movie.title)
                                .font(.app(.headline, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            if let year = movie.year {
                                Text(String(year))
                                    .font(.app(.subheadline))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(tr("Фильм", "Filme", "Movie"))
                } footer: {
                    Text(tr("Набор ляжет в папку «Фильмы».", "O baralho vai para a pasta «Filmes».",
                            "The deck goes into the Movies folder."))
                }
            } else if lessonMode {
                lessonSection(model)
            } else {
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
            }

            if !lessonMode {
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
                            pickingPDF = false
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
            }

            Section {
                Stepper(
                    (lessonMode ? tr("Карточек: до ", "Cartões: até ", "Cards: up to ")
                                : tr("Слов: ", "Palavras: ", "Words: ")) + "\(model.wordCount)",
                    value: $model.wordCount,
                    in: DeckRequest.wordCountRange, step: 5)
                Picker(tr("Мой уровень", "O meu nível", "My level"), selection: $model.level) {
                    Text(tr("Не знаю", "Não sei", "Don't know")).tag(CEFRLevel?.none)
                    ForEach(CEFRLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(CEFRLevel?.some(level))
                    }
                }
                // Без уровня слова подбираются вслепую — на средний B1–B2.
                // Тест занимает три минуты и делает каждый следующий набор точнее.
                if model.level == nil, StudyLanguageStore.shared.current.hasPlacementTest {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(tr("Без уровня подберу слова как для среднего — B1–B2. "
                                    + "Для новичка это будет трудно, для продвинутого — скучно.",
                                 "Sem nível, escolho palavras como para o nível médio — B1–B2. "
                                    + "Para um principiante será difícil, para um avançado, aborrecido.",
                                 "Without a level I'll pick words for an average B1–B2. "
                                    + "Hard for a beginner, boring for an advanced learner."),
                              systemImage: "exclamationmark.triangle")
                            .font(.app(.footnote))
                            .foregroundStyle(Theme.ink)
                        Button {
                            showPlacementTest = true
                        } label: {
                            Label(tr("Узнать уровень — 3 минуты", "Descobrir o nível — 3 minutos",
                                     "Find my level — 3 minutes"),
                                  systemImage: "text.magnifyingglass")
                                .font(.app(.callout, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.chunkySecondary)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text(tr("Слова подбираются на ступень выше твоего уровня — "
                            + "уже не очевидные, но ещё часто встречающиеся.",
                        "As palavras ficam um degrau acima do teu nível — já não óbvias, "
                            + "mas ainda frequentes.",
                        "Words are picked one step above your level — no longer obvious, "
                            + "but still common."))
            }
            .sheet(isPresented: $showPlacementTest) {
                PlacementTestView { level in
                    UserDefaults.standard.set(level.rawValue, forKey: SettingsKey.englishLevel)
                    model.level = level
                }
            }

            if model.usesBackend {
                Section {
                    if let plan = RecapAccount.shared.plan, plan.active {
                        LabeledContent("Recap Plus",
                                       value: "≈ " + Counted.decks(plan.approximateDecksLeft))
                    } else {
                        Label(tr("Для популярных сериалов есть готовые наборы — бесплатно.",
                                 "Há baralhos prontos e grátis para séries populares.",
                                 "Popular shows have ready decks — for free."),
                              systemImage: "books.vertical.fill")
                            .font(.app(.callout))
                    }
                    if model.needsPlan {
                        NavigationLink {
                            PlusView()
                        } label: {
                            Label(tr("Оформить Recap Plus или ввести промокод",
                                     "Obter o Recap Plus ou usar um código",
                                     "Get Recap Plus or use a promo code"),
                                  systemImage: "star.fill")
                        }
                    }
                }
            } else {
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
            }

            if model.step == .working {
                Section {
                    MascotSays(mood: .thinking,
                               text: tr("Подбираю слова… Обычно это 10–20 секунд, "
                                            + "с субтитрами — до минуты.",
                                        "A escolher palavras… Costuma levar 10–20 segundos, "
                                            + "com legendas até um minuto.",
                                        "Picking words… Usually 10–20 seconds, "
                                            + "up to a minute with subtitles."),
                               size: 72)
                }
                .listRowBackground(Color.clear)
            }

            if case .failed(let message) = model.step {
                Section {
                    MascotSays(mood: .oops, text: message, size: 72)
                }
                .listRowBackground(Color.clear)
            }
        }
        .themedScreen()
        // Подсказка «подбираю слова» и ошибка въезжают, а не выскакивают.
        .animation(.app, value: model.step)
        .safeAreaInset(edge: .bottom) {
            submitButton(model)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(onScan: { pages in
                showCamera = false
                let language = StudyLanguageStore.storedCurrent
                appendScan(model) { try await LessonScanner.text(fromImages: pages, language: language) }
            }, onCancel: { showCamera = false })
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            let language = StudyLanguageStore.storedCurrent
            appendScan(model) {
                var images: [Data] = []
                for item in items {
                    if let data = try await item.loadTransferable(type: Data.self) { images.append(data) }
                }
                return try await LessonScanner.text(fromImages: images, language: language)
            }
            photoItems = []
        }
        // Один выбор файла на экран: два .fileImporter на одном виде SwiftUI
        // путает, и открывается только один. Что выбираем — помнит pickingPDF.
        .fileImporter(
            isPresented: Binding(
                get: { showSubtitlePicker || showPDFPicker },
                set: { if !$0 { showSubtitlePicker = false; showPDFPicker = false } }),
            allowedContentTypes: pickingPDF ? [.pdf] : [.plainText, .text, .data]
        ) { outcome in
            guard case .success(let url) = outcome else { return }
            if pickingPDF {
                let language = StudyLanguageStore.storedCurrent
                appendScan(model) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try await LessonScanner.text(fromPDF: url, language: language)
                }
                return
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                model.loadSubtitles(from: data, name: url.lastPathComponent)
            }
        }
    }

    private var apiKeySection: some View {
        let provider = AIKeys.active
        return Section {
            SecureField(tr("Ключ API ", "Chave da API ", "API key: ") + provider.shortName,
                        text: $apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: apiKey) { _, value in
                    AIKeys.setKey(value, for: provider)
                }
            Link(tr("Где взять ключ", "Onde obter a chave", "Where to get a key"),
                 destination: provider.consoleURL)
        } header: {
            Text(tr("Нужен ключ", "É precisa uma chave", "A key is needed"))
        } footer: {
            Text(tr("Ключ хранится в Keychain телефона и уходит только провайдеру. Другой ИИ "
                        + "(Gemini, ChatGPT, Kimi…) — Профиль → Ключи ИИ.",
                    "A chave fica no Keychain do telemóvel e só vai para o fornecedor. Outra IA "
                        + "(Gemini, ChatGPT, Kimi…) — Perfil → Chaves de IA.",
                    "The key stays in the phone's Keychain and only goes to the provider. Another AI "
                        + "(Gemini, ChatGPT, Kimi…) — Profile → AI keys."))
        }
    }

    /// Запуск и продолжение одного и того же запроса. Обрыв из-за
    /// свёрнутого приложения — не ошибка: ни вибрации, ни красного текста.
    private func run(_ model: DeckRequestModel) {
        Task {
            if let generated = await model.generate() {
                Haptics.success()
                plan = PendingImport(plan: generated)
            } else if model.step == .interrupted {
                // Сервер ещё собирает — спросим снова чуть позже, если экран активен.
                if scenePhase == .active {
                    try? await Task.sleep(for: .seconds(3))
                    if model.step == .interrupted { run(model) }
                }
            } else {
                Haptics.failure()
            }
        }
    }

    @ViewBuilder
    private func submitButton(_ model: DeckRequestModel) -> some View {
        Button {
            Haptics.tap()
            topicFocused = false
            AIConsent.run({ run(model) }, pending: $pendingAI)
        } label: {
            HStack(spacing: 10) {
                if model.step == .working || model.step == .interrupted {
                    MonchikLoader(tint: Theme.onPrimary)
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
        .buttonStyle(.chunky)
        .controlSize(.large)
        .disabled(!model.canSubmit || (!model.usesBackend && !model.hasAPIKey && apiKey.isEmpty))
    }

    // MARK: - Итог

    private func doneView(_ result: ImportResult) -> some View {
        VStack(spacing: 20) {
            Spacer()
            MascotView(mood: .cheer, size: 160)
            Text(result.deckName)
                .font(.app(.title2, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(Counted.words(result.addedNotes) + " · " + Counted.cards(result.addedCards))
                .foregroundStyle(Theme.muted)
            if let model, model.lastCost > 0 {
                Text(tr("Стоило ", "Custou ", "Cost ") + String(format: "$%.3f", model.lastCost))
                    .font(.app(.footnote))
                    .foregroundStyle(Theme.muted)
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
            .buttonStyle(.chunky)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
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

#if DEBUG
private struct Previews: View {
    var body: some View {
        DeckRequestView()
            .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#Preview("К серии") { DeckRequestView(episode: PreviewData.episode).previewEnvironment() }
#endif
