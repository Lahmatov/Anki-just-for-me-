import SwiftUI
import SwiftData
import AJFMCore

/// Спряжение (P-69): «comer — nós, presente» → «comemos», затем вся таблица.
struct ConjugationDrillView: View {
    let verbs: [String]

    @State private var tasks: [ConjugationTask] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var check: AnswerCheck?
    @State private var points = 0.0
    @FocusState private var focused: Bool

    private var language: StudyLanguage { StudyLanguageStore.storedCurrent }
    private var task: ConjugationTask? { index < tasks.count ? tasks[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !tasks.isEmpty {
                    ChunkyProgressBar(value: Double(index), total: Double(tasks.count), tint: Theme.orange)
                }
                if let task {
                    card(task)
                } else if !tasks.isEmpty {
                    DrillSummary(points: points, total: tasks.count) { restart() }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("Спряжение", "Conjugação", "Conjugation"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if tasks.isEmpty { restart() } }
    }

    private func card(_ task: ConjugationTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(task.tense.title(for: language).uppercased())
                .font(.app(.caption, weight: .heavy))
                .foregroundStyle(Theme.orange)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.verb).font(.app(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                Text("·").foregroundStyle(Theme.muted)
                Text(task.person).font(.app(.title2, weight: .bold)).foregroundStyle(Theme.primary)
            }
            TextField(tr("Форма глагола", "Forma do verbo", "Verb form"), text: $typed)
                .textFieldStyle(.soft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .disabled(check != nil)
                .onSubmit(submit)
                .accessibilityIdentifier("conjugation.answer")

            if let check {
                Label(check.verdict == .correct ? tr("Верно", "Certo", "Right")
                                                : check.hint ?? task.answer,
                      systemImage: check.verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.app(.headline))
                    .foregroundStyle(check.verdict == .wrong ? Theme.red
                                     : check.verdict == .typo ? Theme.orange : Theme.green)
                table(task)
                Button(index + 1 < tasks.count ? tr("Дальше", "Seguinte", "Next")
                                               : tr("Итог", "Resultado", "Results")) {
                    withAnimation(.app) {
                        index += 1
                        typed = ""
                        self.check = nil
                    }
                    focused = true
                }
                .buttonStyle(.chunky)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("conjugation.next")
            } else {
                Button(tr("Проверить", "Verificar", "Check"), action: submit)
                    .buttonStyle(.chunky)
                    .frame(maxWidth: .infinity)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("conjugation.check")
            }
        }
        .modifier(CardSurface(emphasized: check != nil))
        .onAppear { focused = true }
        .id(task.id)
    }

    /// Вся таблица после ответа: спрошенная строка выделена.
    private func table(_ task: ConjugationTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(task.table.forms, id: \.person) { form in
                HStack {
                    Text(form.person)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 84, alignment: .leading)
                    Text(form.form)
                        .fontWeight(form.person == task.person ? .heavy : .regular)
                        .foregroundStyle(form.person == task.person ? Theme.ink : Theme.muted)
                }
                .font(.app(.callout))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: Theme.orange.opacity(0.08), border: Theme.orange.opacity(0.4), lip: false, radius: 12)
        .accessibilityElement(children: .combine)
    }

    private func submit() {
        guard let task, check == nil, !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Без поблажки на артикль: в спряжении важна каждая буква, но одна
        // опечатка (потерянное ударение «falamos») — полбалла, а не ноль.
        focused = false
        let result = AnswerChecker.check(input: typed, expected: task.answer)
        check = result
        switch result.verdict {
        case .correct: points += 1
        case .typo: points += 0.5
        case .wrong: break
        }
        if result.verdict == .wrong { Haptics.warning() } else { Haptics.success() }
    }

    private func restart() {
        var generator = SystemRandomNumberGenerator()
        tasks = ConjugationDrill.make(verbs: verbs, language: language, using: &generator)
        index = 0
        points = 0
        typed = ""
        check = nil
    }
}

/// Мини-тест урока: десять вопросов на выбор. Результат — в карту уроков.
struct LessonQuizView: View {
    let deck: Deck

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var answers: [Int: String] = [:]
    @State private var finished = false

    private var question: QuizQuestion? { index < questions.count ? questions[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if questions.isEmpty {
                    MascotSays(mood: .thinking,
                               text: tr("Для теста нужно хотя бы два слова в уроке.",
                                        "Para o teste é preciso pelo menos duas palavras.",
                                        "The quiz needs at least two words in the lesson."))
                } else if let question {
                    ChunkyProgressBar(value: Double(index), total: Double(questions.count), tint: Theme.green)
                    card(question)
                } else {
                    result
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("Мини-тест", "Mini-teste", "Mini quiz"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if questions.isEmpty { restart() } }
    }

    private func card(_ question: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.instruction(question.kind))
                .font(.app(.caption, weight: .heavy))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
            Text(question.prompt)
                .font(.app(.title2, weight: .bold))
                .foregroundStyle(Theme.ink)
            ForEach(question.choices, id: \.self) { choice in
                Button {
                    guard answers[question.id] == nil else { return }
                    answers[question.id] = choice
                    if choice == question.answer { Haptics.success() } else { Haptics.warning() }
                } label: {
                    Text(choice)
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .panel(fill: fill(choice, in: question), border: border(choice, in: question),
                               lip: false, radius: 14)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quiz.choice")
            }
            if answers[question.id] != nil {
                Button(index + 1 < questions.count ? tr("Дальше", "Seguinte", "Next")
                                                   : tr("Итог", "Resultado", "Results")) {
                    withAnimation(.app) { index += 1 }
                    if index >= questions.count { finish() }
                }
                .buttonStyle(.chunky)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("quiz.next")
            }
        }
        .modifier(CardSurface())
        .id(question.id)
    }

    private var result: some View {
        let score = LessonQuiz.score(questions, answers: answers)
        let passed = LessonQuiz.passed(score)
        return VStack(spacing: 16) {
            MascotSays(mood: passed ? .cheer : .hello,
                       text: passed
                           ? tr("Зачёт! Урок держится в голове.", "Passaste! A aula ficou na cabeça.",
                                "Passed! The lesson stuck.")
                           : tr("Почти. Потренируйся на тренажёрах и попробуй ещё.",
                                "Quase. Treina um pouco e tenta outra vez.",
                                "Almost. Practise with the trainers and try again."))
            Text("\(Int((score * 100).rounded()))%")
                .font(.app(.largeTitle, weight: .heavy))
                .foregroundStyle(passed ? Theme.green : Theme.ink)
                .accessibilityIdentifier("quiz.score")
            Button(tr("Ещё раз", "Outra vez", "Again")) { restart() }
                .buttonStyle(.chunkySecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fill(_ choice: String, in question: QuizQuestion) -> Color {
        guard let picked = answers[question.id] else { return Theme.surface }
        if choice == question.answer { return Theme.green.opacity(0.15) }
        return choice == picked ? Theme.red.opacity(0.12) : Theme.surface
    }

    private func border(_ choice: String, in question: QuizQuestion) -> Color {
        guard let picked = answers[question.id] else { return Theme.border }
        if choice == question.answer { return Theme.green }
        return choice == picked ? Theme.red : Theme.border
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let score = LessonQuiz.score(questions, answers: answers)
        let wasPassed = LessonLibrary.bestQuiz(for: deck).map(LessonQuiz.passed) ?? false
        LessonLibrary.record(quiz: score, for: deck)
        AnalyticsService.track(.quizFinished(passed: LessonQuiz.passed(score)))
        if LessonQuiz.passed(score), !wasPassed {
            Celebrations.shared.show(
                tr("Тест сдан!", "Teste aprovado!", "Quiz passed!"),
                subtitle: tr("«\(deck.name)» — \(Int((score * 100).rounded()))%",
                             "«\(deck.name)» — \(Int((score * 100).rounded()))%",
                             "“\(deck.name)” — \(Int((score * 100).rounded()))%"))
        }
    }

    private func restart() {
        var generator = SystemRandomNumberGenerator()
        questions = LessonQuiz.make(notes: LessonLibrary.notes(of: deck), using: &generator)
        index = 0
        answers = [:]
        finished = false
    }

    static func instruction(_ kind: QuizQuestion.Kind) -> String {
        switch kind {
        case .meaning: return tr("Что это значит?", "O que significa?", "What does it mean?")
        case .word: return tr("Как это сказать?", "Como se diz?", "How do you say it?")
        case .gap: return tr("Какое слово пропущено?", "Que palavra falta?", "Which word is missing?")
        }
    }
}

/// «Расскажи об уроке»: говоришь вслух на тему урока — видно, какие его
/// слова прозвучали. Рассказ можно отдать Мончику и продолжить разговором.
struct LessonSpeakView: View {
    let deck: Deck
    let notes: [NoteData]

    @State private var recorder = RetellRecorder()
    @State private var result: LessonSpeech.Result?
    @State private var transcript = ""
    @State private var permissionDenied = false

    private var language: StudyLanguage { StudyLanguageStore.storedCurrent }
    private var terms: [String] { notes.map(\.term) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MascotSays(mood: .hello,
                           text: tr("Расскажи \(language.inLanguage), что было на уроке, или придумай "
                                        + "историю. Постарайся вставить слова урока.",
                                    "Conta \(language.inLanguage) o que deste na aula ou inventa uma "
                                        + "história. Tenta usar as palavras da aula.",
                                    "Tell \(language.inLanguage) what the lesson was about, or make up a "
                                        + "story. Try to use the lesson's words."))
                Text(terms.prefix(24).joined(separator: " · "))
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)

                recordButton

                if recorder.isRecording || !recorder.fullText.isEmpty {
                    Text(recorder.fullText.isEmpty ? "…" : recorder.fullText)
                        .font(.app(.body))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(CardSurface())
                }
                if permissionDenied {
                    Label(tr("Нужны разрешения на микрофон и распознавание речи.",
                             "São precisas permissões para o microfone e o reconhecimento de fala.",
                             "Microphone and speech recognition permissions are needed."),
                          systemImage: "exclamationmark.triangle")
                        .font(.app(.callout))
                        .foregroundStyle(Theme.orange)
                }
                if case .failed(let message) = recorder.status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.app(.callout))
                        .foregroundStyle(Theme.orange)
                }
                if let result { report(result) }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("Расскажи об уроке", "Fala sobre a aula", "Talk about the lesson"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            recorder.onInterrupted = nil
            if recorder.isRecording { recorder.stop() }
        }
    }

    private var recordButton: some View {
        Button {
            Haptics.tap()
            if recorder.isRecording { stop() } else { start() }
        } label: {
            Label(recorder.isRecording ? tr("Готово", "Pronto", "Done")
                                       : tr("Говорить", "Falar", "Speak"),
                  systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChunkyButtonStyle(kind: recorder.isRecording ? .destructive : .primary))
        .accessibilityIdentifier("speak.record")
    }

    private func report(_ result: LessonSpeech.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Слов урока прозвучало: \(result.used.count) из \(result.used.count + result.unused.count)",
                    "Palavras da aula usadas: \(result.used.count) de \(result.used.count + result.unused.count)",
                    "Lesson words used: \(result.used.count) of \(result.used.count + result.unused.count)"))
                .font(.app(.headline))
                .foregroundStyle(Theme.ink)
            ChunkyProgressBar(value: result.coverage, tint: Theme.green)
            if !result.used.isEmpty {
                Label(result.used.joined(separator: ", "), systemImage: "checkmark.circle.fill")
                    .font(.app(.callout))
                    .foregroundStyle(Theme.green)
            }
            if !result.unused.isEmpty {
                Label(tr("Не прозвучали: ", "Faltaram: ", "Not used: ") + result.unused.prefix(12)
                        .joined(separator: ", "),
                      systemImage: "circle.dashed")
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
            }
            NavigationLink(value: AppRoute.lessonChat(deck.persistentModelID, retelling: transcript)) {
                Label(tr("Обсудить с Мончиком", "Conversar com o Monchik", "Discuss with Monchik"),
                      systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.chunkySecondary)
            .accessibilityIdentifier("speak.chat")
        }
        .modifier(CardSurface())
    }

    private func start() {
        Task {
            guard await PronunciationService.requestPermissions() else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            result = nil
            SpeechService.shared.stop()
            recorder.reset()
            // Звонок или наушники — разбираем то, что успел сказать (P-80).
            recorder.onInterrupted = { stop() }
            recorder.start()
        }
    }

    private func stop() {
        // Замыкание держит копию экрана, а экран — рекордер: без обнуления
        // рекордер с аудиодвижком не освободится после ухода с экрана.
        recorder.onInterrupted = nil
        recorder.stop()
        transcript = recorder.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        withAnimation(.app) {
            result = LessonSpeech.check(transcript: transcript, terms: terms, language: language)
        }
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        RoutedStack {
            LessonQuizView(deck: PreviewData.lessonDeck)
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#Preview("Спряжение") { RoutedStack { ConjugationDrillView(verbs: ["go", "travel"]) }.previewEnvironment() }
#endif
