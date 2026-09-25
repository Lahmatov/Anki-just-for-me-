import SwiftUI
import SwiftData
import AJFMCore

struct ReviewSessionView: View {
    /// nil — повторяем всё, что подошло по сроку, из всех наборов.
    let deck: Deck?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReviewSessionModel?

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
        .navigationTitle(deck?.name ?? "Повторение")
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
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                sessionCaption(model)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: Design.stackSpacing) {
                    if let card = model.current {
                        CardPromptView(card: card, model: model)
                            .cardSurface(emphasized: model.isRevealed)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                footer(model)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Слой управления сессией. Стекло — только здесь, над карточкой:
    /// сама карточка — содержимое и остаётся плотной.
    @ViewBuilder
    private func footer(_ model: ReviewSessionModel) -> some View {
        GlassEffectContainer(spacing: 12) {
            footerContent(model)
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
                    Text("Проверить")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else if model.current?.type == .pronunciation {
                Button {
                    Haptics.tap()
                    model.reveal()
                } label: {
                    Text("Показать")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }

    /// Счёт сессии — рядом с полосой прогресса, а не в стеклянном подвале:
    /// под стеклом мелкий серый текст сливается с карточкой, которая
    /// прокручивается под ним.
    private func sessionCaption(_ model: ReviewSessionModel) -> some View {
        HStack(spacing: 12) {
            Text("\(model.index + 1) из \(model.cards.count)")
                .contentTransition(.numericText())
            if model.stats.answered > 0 {
                Text("·")
                Text("верно \(model.stats.correct + model.stats.typos) "
                     + "из \(model.stats.answered)")
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .animation(.snappy, value: model.index)
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
                .foregroundStyle(.secondary)

            prompt

            if card.type == .recognition, !model.isRevealed {
                choices
            }

            if card.type.requiresTyping, !model.isRevealed {
                TextField("Ответ", text: Binding(
                    get: { model.typedAnswer },
                    set: { model.typedAnswer = $0 }))
                    .textFieldStyle(.roundedBorder)
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
                    SpeakButton(text: spokenText, label: "Прослушать")
                    SpeakButton(text: spokenText, rate: .slow, label: "Медленно")
                }
                Text("Можно слушать сколько угодно раз.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        case .spelling:
            VStack(alignment: .leading, spacing: 12) {
                Text(note?.translation ?? "").font(.app(.title, weight: .bold))
                HStack {
                    SpeakButton(text: note?.term ?? "", label: "Прослушать")
                    SpeakButton(text: note?.term ?? "", rate: .slow, label: "Медленно")
                }
            }
        case .pronunciation:
            VStack(alignment: .leading, spacing: 8) {
                Text(note?.term ?? "").font(.app(.largeTitle, weight: .bold))
                if let ipa = note?.ipa, !ipa.isEmpty {
                    Text(ipa).font(.ipa(.body)).foregroundStyle(.secondary)
                }
                SpeakButton(text: note?.term ?? "", rate: .slow, label: "Медленно")
                PronunciationRecorderView(word: note?.term ?? "")
                if let pair = MinimalPairLibrary.pair(containing: note?.term ?? "") {
                    Text("Это слово из минимальной пары «\(pair.first) — \(pair.second)». "
                         + "Вкладка «Речь» проверит его строже.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
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
                .buttonStyle(.bordered)
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
                    Text(hint).font(.app(.subheadline)).foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text(note?.term ?? "").font(.app(.title2, weight: .bold))
                SpeakButton(text: note?.term ?? "", compact: true)
            }
            if let ipa = note?.ipa, !ipa.isEmpty {
                Text(ipa).font(.ipa(.body)).foregroundStyle(.secondary)
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
                Text(translation).font(.app(.caption)).foregroundStyle(.secondary)
            }
            if let userNote = note?.userNote, !userNote.isEmpty {
                Text(userNote).font(.app(.caption)).foregroundStyle(.orange)
            }
        }
    }

    private func verdictText(_ check: AnswerCheck) -> String {
        switch check.verdict {
        case .correct: return "Верно"
        case .typo: return "Почти — опечатка"
        case .wrong: return "Неверно"
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
                Text(grade.title).font(.app(.callout, weight: .medium))
                // Интервал прямо на кнопке: выбор оценки должен быть
                // осознанным, а не гаданием.
                Text(model.interval(for: grade))
                    .font(.app(.caption2))
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .controlSize(.large)

        if model.suggestedGrade == grade {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
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

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            if stats.answered > 0 {
                accuracyRing
                Text("Сессия закончена")
                    .font(.app(.title2, weight: .bold))
                HStack(spacing: 10) {
                    tile("Верно", stats.correct, .green)
                    tile("Опечатки", stats.typos, .orange)
                    tile("Мимо", stats.wrong, .red)
                }
            } else {
                IconBadge(systemName: "checkmark", color: .green, size: 72)
                VStack(spacing: 8) {
                    Text("На сегодня всё")
                        .font(.app(.title2, weight: .bold))
                    Text("Карточек по сроку нет. Возвращайся позже — или добавь новый набор.")
                        .font(.app(.subheadline))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onDone) {
                Text("Готово")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding()
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                shownAccuracy = stats.accuracy
            }
        }
    }

    /// Точность кольцом: цифра, ради которой сессию и проходят,
    /// должна читаться с первого взгляда.
    private var accuracyRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 14)
            Circle()
                .trim(from: 0, to: shownAccuracy)
                .stroke(ringColor.gradient,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((stats.accuracy * 100).rounded()))%")
                    .font(.app(.largeTitle, weight: .heavy))
                    .monospacedDigit()
                Text("точность")
                    .font(.app(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .combine)
    }

    private var ringColor: Color {
        switch stats.accuracy {
        case 0.9...: return .green
        case 0.7..<0.9: return .accentColor
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
    }
}
