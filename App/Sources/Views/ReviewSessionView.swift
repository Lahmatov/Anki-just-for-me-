import SwiftUI
import SwiftData
import AJFMCore

struct ReviewSessionView: View {
    /// nil — повторяем всё, что подошло по сроку, из всех наборов.
    let deck: Deck?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ReviewSessionModel?
    /// Счётчик ответов — будит реакцию Мончика даже на два одинаковых вердикта подряд.
    @State private var reactions = 0
    /// Растёт на единицу с каждым неверным ответом: одно покачивание карточки.
    @State private var shakes: CGFloat = 0

    var body: some View {
        Group {
            if let model {
                if model.isFinished {
                    SessionSummaryView(stats: model.stats) { dismiss() }
                        .onAppear {
                            ProgressService.recordSessionResult(
                                accurate: model.stats.answered > 0 && model.stats.wrong == 0)
                        }
                } else {
                    sessionBody(model)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(deck?.name ?? tr("Повторение", "Revisão", "Review"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model == nil {
                let created = ReviewSessionModel(context: context)
                created.load(deck: deck)
                model = created
            }
        }
    }

    @ViewBuilder
    private func sessionBody(_ model: ReviewSessionModel) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ChunkyProgressBar(value: model.progress)
                    .accessibilityIdentifier("session.progress")
                sessionCaption(model)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: Design.stackSpacing) {
                    if let card = model.current {
                        // Новая карточка въезжает справа, старая уходит влево —
                        // видно, что колода движется, а не текст подменился.
                        CardPromptView(card: card, model: model)
                            .cardSurface(emphasized: model.isRevealed)
                            .modifier(ShakeEffect(trigger: shakes))
                            .id(card.persistentModelID)
                            .transition(cardTransition)
                    }
                }
                .padding()
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3),
                           value: model.index)
            }
            .onChange(of: model.isRevealed) { _, revealed in
                guard revealed else { return }
                reactions += 1
                if model.check?.verdict == .wrong, !reduceMotion {
                    withAnimation(.linear(duration: 0.45)) { shakes += 1 }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer(model)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.background)
    }

    /// Слой управления сессией. Стекло — только здесь, над карточкой:
    /// сама карточка — содержимое и остаётся плотной.
    @ViewBuilder
    private func footer(_ model: ReviewSessionModel) -> some View {
        let hasControls = model.isRevealed
            || model.current?.type.requiresTyping == true
            || model.current?.type == .pronunciation
        if hasControls {
            footerContent(model)
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    @ViewBuilder
    private func footerContent(_ model: ReviewSessionModel) -> some View {
        VStack(spacing: 10) {
            if model.isRevealed {
                GradeButtons(model: model)
            } else if model.current?.type.requiresTyping == true {
                Button {
                    Haptics.tap()
                    model.reveal()
                } label: {
                    Text(tr("Проверить", "Verificar", "Check"))
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky)
                .controlSize(.large)
            } else if model.current?.type == .pronunciation {
                Button {
                    Haptics.tap()
                    model.reveal()
                } label: {
                    Text(tr("Показать", "Mostrar", "Show"))
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky)
                .controlSize(.large)
            }
        }
    }

    /// Счёт сессии — рядом с полосой прогресса, а не в стеклянном подвале:
    /// под стеклом мелкий серый текст сливается с карточкой, которая
    /// прокручивается под ним.
    private func sessionCaption(_ model: ReviewSessionModel) -> some View {
        HStack(spacing: 12) {
            Text("\(model.index + 1) " + tr("из", "de", "of") + " \(model.cards.count)")
                .contentTransition(.numericText())
            if model.stats.answered > 0 {
                Text("·")
                Text(tr("верно", "certas", "correct")
                     + " \(model.stats.correct + model.stats.typos) "
                     + tr("из", "de", "of") + " \(model.stats.answered)")
                    .contentTransition(.numericText())
            }
            Spacer()
            MascotReactionView(verdict: model.isRevealed ? model.check?.verdict : nil,
                               trigger: reactions, size: 40)
        }
        .font(.app(.caption))
        .foregroundStyle(Theme.muted)
        .monospacedDigit()
        .animation(.snappy, value: model.index)
    }

    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                          removal: .move(edge: .leading).combined(with: .opacity))
    }
}

struct CardPromptView: View {
    let card: Card
    let model: ReviewSessionModel

    private var note: Note? { card.note }

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true

    /// Озвучивается ровно то, что потом проверяется. Соблазн проигрывать
    /// пример целиком велик, но тогда на слух звучит фраза, а ответом ждут
    /// одно слово — и пользователь оказывается неправ на ровном месте.
    /// Пример можно послушать после ответа.
    private var spokenText: String { card.note?.term ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(card.type.instruction)
                .font(.app(.caption))
                .foregroundStyle(Theme.muted)

            prompt

            if card.type == .recognition, !model.isRevealed {
                choices
            }

            if card.type.requiresTyping, !model.isRevealed {
                TextField(tr("Ответ", "Resposta", "Answer"), text: Binding(
                    get: { model.typedAnswer },
                    set: { model.typedAnswer = $0 }))
                    .textFieldStyle(.soft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.app(.title3))
                    .onSubmit { model.reveal() }
            }

            if model.isRevealed {
                answer
            }
        }
        .onAppear { speakPromptIfNeeded() }
        .onChange(of: card.persistentModelID) { _, _ in speakPromptIfNeeded() }
        .onChange(of: model.isRevealed) { _, revealed in
            guard revealed else { return }
            switch model.check?.verdict {
            case .correct: Haptics.success()
            case .typo: Haptics.warning()
            case .wrong: Haptics.failure()
            case nil: break
            }
            if autoSpeak, card.type != .listening {
                SpeechService.shared.speak(card.note?.term ?? "")
            }
        }
    }

    /// Карточку на слух озвучиваем сразу: без звука на ней просто нечего делать.
    private func speakPromptIfNeeded() {
        guard card.type == .listening, autoSpeak else { return }
        SpeechService.shared.speak(spokenText)
    }

    @ViewBuilder
    private var prompt: some View {
        switch card.type {
        case .recognition:
            Text(note?.term ?? "")
                .font(.app(.largeTitle, weight: .semibold))
        case .recall:
            Text(note?.translation ?? "")
                .font(.app(.title, weight: .semibold))
        case .cloze:
            Text(note?.cloze ?? note?.example ?? note?.translation ?? "")
                .font(.app(.title2))
        case .listening:
            // Ни слова, ни перевода на экране: смысл карточки в том,
            // чтобы разобрать речь на слух, а не прочитать подсказку.
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SpeakButton(text: spokenText, label: CommonText.listen)
                    SpeakButton(text: spokenText, rate: .slow, label: SpeechRate.slow.title)
                }
                Text(tr("Можно слушать сколько угодно раз.", "Podes ouvir quantas vezes quiseres.",
                        "Listen as many times as you like."))
                    .font(.app(.caption))
                    .foregroundStyle(Theme.muted)
            }
        case .spelling:
            VStack(alignment: .leading, spacing: 12) {
                Text(note?.translation ?? "").font(.app(.title, weight: .bold))
                HStack {
                    SpeakButton(text: note?.term ?? "", label: CommonText.listen)
                    SpeakButton(text: note?.term ?? "", rate: .slow, label: SpeechRate.slow.title)
                }
            }
        case .pronunciation:
            VStack(alignment: .leading, spacing: 8) {
                Text(note?.term ?? "").font(.app(.largeTitle, weight: .bold))
                if let ipa = note?.ipa, !ipa.isEmpty {
                    Text(ipa).font(.ipa(.body)).foregroundStyle(Theme.muted)
                }
                SpeakButton(text: note?.term ?? "", rate: .slow, label: SpeechRate.slow.title)
                PronunciationRecorderView(word: note?.term ?? "")
                if let pair = MinimalPairLibrary.pair(containing: note?.term ?? "") {
                    Text(tr("Это слово из минимальной пары «\(pair.first) — \(pair.second)». "
                                + "Вкладка «Речь» проверит его строже.",
                            "Esta palavra faz parte do par mínimo «\(pair.first) — \(pair.second)». "
                                + "O separador «Fala» verifica-a com mais rigor.",
                            "This word is part of the minimal pair “\(pair.first) — \(pair.second)”. "
                                + "The Speech tab checks it more strictly."))
                        .font(.app(.caption))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder
    private var choices: some View {
        VStack(spacing: 8) {
            ForEach(model.choices, id: \.self) { option in
                Button {
                    Haptics.tap()
                    model.choose(option)
                } label: {
                    Text(option)
                        .font(.app(.body))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.chunkySecondary)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var answer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let check = model.check {
                Label(verdictText(check), systemImage: verdictIcon(check))
                    .foregroundStyle(verdictColor(check))
                    .font(.app(.headline))
                    .symbolEffect(.bounce, value: check.verdict)
                if let hint = check.hint {
                    Text(hint).font(.app(.subheadline)).foregroundStyle(Theme.muted)
                }
            }

            Divider()

            HStack {
                Text(note?.term ?? "").font(.app(.title2, weight: .bold))
                SpeakButton(text: note?.term ?? "", compact: true)
            }
            if let ipa = note?.ipa, !ipa.isEmpty {
                Text(ipa).font(.ipa(.body)).foregroundStyle(Theme.muted)
            }
            Text(note?.translation ?? "").font(.app(.body))

            if let example = note?.example, !example.isEmpty {
                HStack(alignment: .top) {
                    Text(example).font(.app(.callout)).italic()
                    SpeakButton(text: example, compact: true)
                }
                .padding(.top, 4)
            }
            if let translation = note?.exampleTranslation, !translation.isEmpty {
                Text(translation).font(.app(.caption)).foregroundStyle(Theme.muted)
            }
            if let userNote = note?.userNote, !userNote.isEmpty {
                Text(userNote).font(.app(.caption)).foregroundStyle(.orange)
            }
        }
    }

    private func verdictText(_ check: AnswerCheck) -> String {
        switch check.verdict {
        case .correct: return tr("Верно", "Certo", "Correct")
        case .typo: return tr("Почти — опечатка", "Quase — uma gralha", "Almost — a typo")
        case .wrong: return tr("Неверно", "Errado", "Wrong")
        }
    }

    private func verdictIcon(_ check: AnswerCheck) -> String {
        switch check.verdict {
        case .correct: return "checkmark.circle"
        case .typo: return "exclamationmark.circle"
        case .wrong: return "xmark.circle"
        }
    }

    private func verdictColor(_ check: AnswerCheck) -> Color {
        switch check.verdict {
        case .correct: return .green
        case .typo: return .orange
        case .wrong: return .red
        }
    }
}

struct GradeButtons: View {
    let model: ReviewSessionModel

    /// Оценку, которую подсказывает проверка ответа, выделяем плотным стеклом —
    /// выбор остаётся за человеком, но очевидный вариант под пальцем.
    @ViewBuilder
    private func gradeButton(_ grade: Grade) -> some View {
        let button = Button {
            Haptics.tap()
            model.grade(grade)
        } label: {
            VStack(spacing: 2) {
                // Одной строкой всегда: слово, разорванное на «Хорош/о»,
                // читается хуже, чем чуть уменьшенное.
                Text(grade.title)
                    .font(.app(.callout, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // Интервал прямо на кнопке: выбор оценки должен быть
                // осознанным, а не гаданием.
                Text(model.interval(for: grade))
                    .font(.app(.caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .controlSize(.large)
        .buttonStyle(ChunkyButtonStyle(kind: model.suggestedGrade == grade ? .primary : .secondary,
                                       horizontalPadding: 4))

        button
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases, id: \.rawValue) { grade in
                gradeButton(grade)
            }
        }
    }
}

struct SessionSummaryView: View {
    let stats: SessionStats
    var onDone: () -> Void

    @State private var shownAccuracy = 0.0

    private var level: Celebration.Level {
        Celebration.session(answered: stats.answered, accuracy: stats.accuracy)
    }

    var body: some View {
        content
            .background {
                // Сияние — только за отличную сессию: праздник должен что-то значить.
                if level == .big {
                    AuroraBackground(intensity: 0.45)
                } else {
                    Theme.background.ignoresSafeArea()
                }
            }
            .overlay {
                if level == .big { ConfettiView(origin: (0.5, 0.25)) }
            }
            .onAppear {
                if level == .big { Haptics.success() }
            }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Spacer()

            if stats.answered > 0 {
                MascotView(mood: level == .none ? .hello : .cheer, size: 120)
                accuracyRing
                Text(tr("Сессия закончена", "Sessão terminada", "Session complete"))
                    .font(.app(.title2, weight: .bold))
                HStack(spacing: 10) {
                    tile(tr("Верно", "Certas", "Correct"), stats.correct, Theme.green)
                    tile(tr("Опечатки", "Gralhas", "Typos"), stats.typos, Theme.orange)
                    tile(tr("Мимо", "Erradas", "Wrong"), stats.wrong, Theme.red)
                }
            } else {
                MascotView(mood: .sleepy, size: 160)
                VStack(spacing: 8) {
                    Text(tr("На сегодня всё", "Por hoje é tudo", "All done for today"))
                        .font(.app(.title2, weight: .bold))
                    Text(tr("Карточек по сроку нет. Возвращайся позже — или добавь новый набор.",
                            "Não há cartões para agora. Volta mais tarde — ou junta um baralho novo.",
                            "No cards are due. Come back later — or add a new deck."))
                        .font(.app(.subheadline))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            Button(action: onDone) {
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                shownAccuracy = stats.accuracy
            }
        }
    }

    /// Точность крупной цифрой и толстой полосой: цифра,
    /// ради которой сессию и проходят, должна читаться с первого взгляда.
    private var accuracyRing: some View {
        VStack(spacing: 14) {
            // Цифра набегает вместе с полосой: «0 → 92%» читается как итог работы.
            CountingText(value: shownAccuracy * 100, suffix: "%")
                .font(.hero(56))
                .monospacedDigit()
            ChunkyProgressBar(value: shownAccuracy, tint: ringColor)
            Text(tr("точность", "precisão", "accuracy"))
                .font(.app(.caption, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
        }
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private var ringColor: Color {
        switch stats.accuracy {
        case 0.9...: return .green
        case 0.7..<0.9: return Theme.primary
        default: return .orange
        }
    }

    private func tile(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.app(.title2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value == 0 ? Color.secondary : color)
            Text(title)
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .panel()
    }
}
