import SwiftUI
import SwiftData
import AJFMCore

/// Разговор с Мончиком о серии или об уроке: он спрашивает, ты отвечаешь
/// голосом или текстом, после каждого ответа — одна поправка.
struct EpisodeDiscussionView: View {
    let topic: DiscussionTopic
    var retelling: String?
    /// Длина разговора: в Recap — три вопроса вместо шести.
    var questions: Int = EpisodeDiscussion.maxLearnerTurns
    /// Разговор закончен — для шагов Recap.
    var onFinish: (() -> Void)?

    init(episode: EpisodeContext, retelling: String? = nil,
         questions: Int = EpisodeDiscussion.maxLearnerTurns, onFinish: (() -> Void)? = nil) {
        self.topic = .episode(episode)
        self.retelling = retelling
        self.questions = questions
        self.onFinish = onFinish
    }

    init(lesson: LessonTopic, retelling: String? = nil) {
        self.topic = .lesson(lesson)
        self.retelling = retelling
    }

    private var isLesson: Bool {
        if case .lesson = topic { return true }
        return false
    }

    @Environment(\.modelContext) private var context
    @State private var model: EpisodeDiscussionViewModel?
    @State private var pendingAI: (() -> Void)?
    @State private var deckResult: ImportResult?
    @FocusState private var inputFocused: Bool

    private var speakPrompt: String {
        let language = StudyLanguageStore.storedCurrent.inLanguage
        return tr("Говори \(language)…", "Fala \(language)…", "Speak \(language)…")
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                MonchikLoader(large: true)
            }
        }
        .navigationTitle(isLesson ? tr("Разговор об уроке", "Conversa sobre a aula", "Lesson chat")
                                  : tr("Разговор о серии", "Conversa sobre o episódio", "Episode chat"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background.ignoresSafeArea())
        .aiConsentAlert(pending: $pendingAI)
        .onAppear {
            guard model == nil else { return }
            let created = EpisodeDiscussionViewModel(
                context: context, topic: topic, retelling: retelling, questions: questions)
            model = created
            AIConsent.run({ Task { await created.start() } }, pending: $pendingAI)
        }
        .onChange(of: model?.step) { _, step in
            if step == .finished { onFinish?() }
        }
        .onDisappear {
            if model?.step == .recording { model?.stopRecording() }
            SpeechService.shared.stop()
        }
        .alert(
            tr("Набор создан", "Baralho criado", "Deck created"),
            isPresented: Binding(get: { deckResult != nil }, set: { if !$0 { deckResult = nil } })
        ) {
            Button(CommonText.ok) { deckResult = nil }
        } message: {
            if let deckResult {
                Text("«\(deckResult.deckName)»: \(Counted.words(deckResult.addedNotes)).")
            }
        }
    }

    @ViewBuilder
    private func content(_ model: EpisodeDiscussionViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(topic.title)
                            .font(.app(.headline))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)

                        // AI Act, ст. 50: собеседник должен знать, что говорит
                        // с ИИ, — с 2 августа 2026 это обязанность, а не вежливость.
                        Label(isLesson
                              ? tr("Мончик — ИИ (Claude). Он может ошибаться.",
                                   "O Monchik é uma IA (Claude). Pode enganar-se.",
                                   "Monchik is an AI (Claude). He can make mistakes.")
                              : tr("Мончик — ИИ (Claude). Он может ошибаться в деталях серии.",
                                   "O Monchik é uma IA (Claude). Pode enganar-se nos detalhes.",
                                   "Monchik is an AI (Claude). He may get episode details wrong."),
                              systemImage: "sparkles")
                            .font(.app(.caption))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)

                        ForEach(model.turns) { turn in
                            bubble(turn).id(turn.id)
                        }

                        status(model).id("status")
                    }
                    .padding()
                }
                .onChange(of: model.turns.count) { _, _ in
                    withAnimation { proxy.scrollTo("status", anchor: .bottom) }
                }
            }

            if model.step != .finished {
                inputBar(model)
            }
        }
    }

    // MARK: - Реплики

    @ViewBuilder
    private func bubble(_ turn: EpisodeDiscussion.Turn) -> some View {
        switch turn.speaker {
        case .monchik:
            VStack(alignment: .leading, spacing: 8) {
                if let tip = turn.tip {
                    tipCard(tip)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    MascotView(mood: .hello, size: 40)
                    HStack(alignment: .top) {
                        Text(turn.text)
                            .font(.app(.body))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        SpeakButton(text: turn.text, compact: true)
                    }
                    .padding(12)
                    .panel(radius: 16)
                }
            }
            .padding(.trailing, 32)
        case .learner:
            HStack {
                Spacer(minLength: 48)
                Text(turn.text)
                    .font(.app(.body))
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .panel(fill: Theme.tint, border: Theme.primary.opacity(0.5), lip: false,
                           radius: 16)
            }
        }
    }

    private func tipCard(_ tip: EpisodeDiscussion.Tip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tr("Как сказать лучше", "Como dizer melhor", "A better way to say it"),
                  systemImage: "lightbulb.fill")
                .font(.app(.caption, weight: .heavy))
                .foregroundStyle(Theme.orange)
            HStack(spacing: 6) {
                Text(tip.said).strikethrough().foregroundStyle(Theme.muted)
                Image(systemName: "arrow.right").font(.app(.caption2))
                Text(tip.better).font(.app(.body, weight: .bold)).foregroundStyle(Theme.ink)
            }
            .font(.app(.callout))
            if !tip.why.isEmpty {
                Text(tip.why).font(.app(.caption)).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: Theme.orange.opacity(0.1), border: Theme.orange.opacity(0.6), lip: false,
               radius: 14)
    }

    @ViewBuilder
    private func status(_ model: EpisodeDiscussionViewModel) -> some View {
        switch model.step {
        case .notStarted, .thinking:
            HStack(spacing: 8) {
                MonchikLoader()
                Text(tr("Мончик думает…", "O Monchik está a pensar…", "Monchik is thinking…"))
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                MascotSays(mood: .oops, text: message, size: 64)
                Button(tr("Ещё раз", "Tentar de novo", "Try again")) {
                    Task { await model.retry() }
                }
                .buttonStyle(.chunkySecondary)
            }
        case .finished:
            VStack(spacing: 12) {
                MascotSays(mood: .cheer,
                           text: isLesson
                               ? tr("Классно поболтали! Слова урока уже звучат.",
                                    "Que boa conversa! As palavras da aula já saem.",
                                    "Great chat! The lesson's words are already coming out.")
                               : tr("Классно поболтали! Приходи после следующей серии.",
                                    "Que boa conversa! Volta depois do próximo episódio.",
                                    "Great chat! Come back after the next episode."))
                if model.tipCount > 0 {
                    Button {
                        deckResult = model.makeDeck()
                        Haptics.success()
                    } label: {
                        Label(tr("Поправки — в карточки", "Correções em cartões",
                                 "Turn tips into cards"),
                              systemImage: "rectangle.stack.badge.plus")
                            .font(.app(.headline))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.chunky)
                }
            }
        case .waitingForAnswer, .recording:
            Text(tr("Вопрос ", "Pergunta ", "Question ")
                 + "\(model.questionNumber)/\(model.questions)")
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Ввод

    private func inputBar(_ model: EpisodeDiscussionViewModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 6) {
            if model.step == .recording {
                Text(model.recorder.fullText.isEmpty
                     ? speakPrompt
                     : model.recorder.fullText)
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    if model.step == .recording { model.stopRecording() } else { model.startRecording() }
                } label: {
                    Image(systemName: model.step == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 22)
                }
                .buttonStyle(ChunkyButtonStyle(kind: model.step == .recording ? .destructive : .secondary))
                .disabled(model.step != .waitingForAnswer && model.step != .recording)
                .accessibilityLabel(tr("Ответить голосом", "Responder por voz", "Answer by voice"))

                TextField(tr("Твой ответ", "A tua resposta", "Your answer"),
                          text: $model.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.soft)
                    .focused($inputFocused)

                Button {
                    Haptics.tap()
                    inputFocused = false
                    AIConsent.run({ Task { await model.send() } }, pending: $pendingAI)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .heavy))
                        .frame(width: 22)
                }
                .buttonStyle(.chunky)
                .disabled(!model.canSend)
                .accessibilityLabel(tr("Отправить", "Enviar", "Send"))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        RoutedStack {
            EpisodeDiscussionView(episode: PreviewData.episode)
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#Preview("Урок") { RoutedStack { EpisodeDiscussionView(lesson: PreviewData.lessonTopic) }.previewEnvironment() }
#endif
