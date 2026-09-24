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
                        .font(.headline)
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
                        .font(.headline)
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
        .font(.caption)
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
                .font(.caption)
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
                    .font(.title3)
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
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
        case .recall:
            Text(note?.translation ?? "")
                .font(.system(.title, design: .rounded, weight: .semibold))
        case .cloze:
            Text(note?.cloze ?? note?.example ?? note?.translation ?? "")
                .font(.title2)
        case .listening:
            // Ни слова, ни перевода на экране: смысл карточки в том,
            // чтобы разобрать речь на слух, а не прочитать подсказку.
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SpeakButton(text: spokenText, label: "Прослушать")
                    SpeakButton(text: spokenText, rate: .slow, label: "Медленно")
                }
                Text("Можно слушать сколько угодно раз.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .spelling:
            VStack(alignment: .leading, spacing: 12) {
                Text(note?.translation ?? "").font(.title).bold()
                HStack {
                    SpeakButton(text: note?.term ?? "", label: "Прослушать")
                    SpeakButton(text: note?.term ?? "", rate: .slow, label: "Медленно")
                }
            }
        case .pronunciation:
            VStack(alignment: .leading, spacing: 8) {
                Text(note?.term ?? "").font(.largeTitle).bold()
                if let ipa = note?.ipa, !ipa.isEmpty {
                    Text(ipa).foregroundStyle(.secondary)
                }
                SpeakButton(text: note?.term ?? "", rate: .slow, label: "Медленно")
                PronunciationRecorderView(word: note?.term ?? "")
                if let pair = MinimalPairLibrary.pair(containing: note?.term ?? "") {
                    Text("Это слово из минимальной пары «\(pair.first) — \(pair.second)». "
                         + "Вкладка «Речь» проверит его строже.")
                        .font(.caption)
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
                        .font(.body)
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
                    .font(.headline)
                    .symbolEffect(.bounce, value: check.verdict)
                if let hint = check.hint {
                    Text(hint).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text(note?.term ?? "").font(.title2).bold()
                SpeakButton(text: note?.term ?? "", compact: true)
            }
            if let ipa = note?.ipa, !ipa.isEmpty {
                Text(ipa).foregroundStyle(.secondary)
            }
            Text(note?.translation ?? "").font(.body)

            if let example = note?.example, !example.isEmpty {
                HStack(alignment: .top) {
                    Text(example).font(.callout).italic()
                    SpeakButton(text: example, compact: true)
                }
                .padding(.top, 4)
            }
            if let translation = note?.exampleTranslation, !translation.isEmpty {
                Text(translation).font(.caption).foregroundStyle(.secondary)
            }
            if let userNote = note?.userNote, !userNote.isEmpty {
                Text(userNote).font(.caption).foregroundStyle(.orange)
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
                Text(grade.title).font(.callout.weight(.medium))
                // Интервал прямо на кнопке: выбор оценки должен быть
                // осознанным, а не гаданием.
                Text(model.interval(for: grade))
                    .font(.caption2)
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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: stats.answered == 0 ? "checkmark.circle" : "flag.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(stats.answered == 0 ? "На сегодня всё" : "Сессия закончена")
                .font(.title2).bold()

            if stats.answered > 0 {
                VStack(spacing: 6) {
                    Text("Отвечено: \(stats.answered)")
                    Text("Верно: \(stats.correct) · опечаток: \(stats.typos) · мимо: \(stats.wrong)")
                        .foregroundStyle(.secondary)
                    Text("Точность: \(Int(stats.accuracy * 100))%")
                        .font(.headline)
                }
                .font(.subheadline)
            } else {
                Text("Карточек по сроку нет. Возвращайся позже — или добавь новый набор.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Button(action: onDone) {
                Text("Готово").font(.headline).frame(maxWidth: 220)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
