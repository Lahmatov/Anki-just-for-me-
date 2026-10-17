import SwiftUI
import AJFMCore

/// Тренажёр урока (P-69): перевод, пропуски, диктант или произношение.
/// Расписание повторений не трогает — гоняй сколько хочешь.
struct LessonDrillView: View {
    let notes: [NoteData]
    let mode: DrillMode

    @State private var items: [DrillItem] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var check: AnswerCheck?
    @State private var dictation: DictationResult?
    @State private var points = 0.0
    /// Произношение: засчитанные слова — по разу, сколько бы попыток ни было.
    @State private var accepted: Set<Int> = []
    @FocusState private var focused: Bool

    private var item: DrillItem? { index < items.count ? items[index] : nil }
    private var isChecked: Bool { check != nil || dictation != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !items.isEmpty {
                    ChunkyProgressBar(value: Double(index), total: Double(items.count))
                }
                if let item {
                    task(item)
                } else if !items.isEmpty {
                    DrillSummary(points: mode == .pronunciation ? Double(accepted.count) : points,
                                 total: items.count) { restart() }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if items.isEmpty { restart() } }
        .onDisappear { SpeechService.shared.stop() }
    }

    @ViewBuilder
    private func task(_ item: DrillItem) -> some View {
        switch mode {
        case .pronunciation:
            VStack(alignment: .leading, spacing: 12) {
                Text(item.prompt)
                    .font(.app(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let hint = item.hint {
                    Text(hint).font(.app(.callout)).foregroundStyle(Theme.muted)
                }
                SpeakButton(text: item.spoken ?? item.prompt, rate: .slow, label: SpeechRate.slow.title)
                PronunciationRecorderView(word: item.answer) { assessment in
                    if assessment.isAccepted { accepted.insert(item.id) }
                }
                .id(item.id)
                nextButton
            }
            .modifier(CardSurface())
        default:
            VStack(alignment: .leading, spacing: 14) {
                if mode == .dictation {
                    HStack {
                        SpeakButton(text: item.spoken ?? item.answer,
                                    label: tr("Слушать", "Ouvir", "Listen"))
                        SpeakButton(text: item.spoken ?? item.answer, rate: .slow, label: SpeechRate.slow.title)
                    }
                } else {
                    Text(item.prompt)
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                if let hint = item.hint {
                    Text(hint).font(.app(.callout)).foregroundStyle(Theme.muted)
                }
                TextField(mode == .dictation ? tr("Что услышал", "O que ouviste", "What you heard")
                                             : tr("Ответ", "Resposta", "Answer"),
                          text: $typed)
                    // Одна строка: «Ввод» проверяет ответ, а не переносит строку.
                    .submitLabel(.done)
                    .textFieldStyle(.soft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .disabled(isChecked)
                    .onSubmit(submit)
                    .accessibilityIdentifier("drill.answer")

                if let check { verdict(check, item: item) }
                if let dictation { DictationWords(result: dictation, expected: item.answer) }

                if isChecked {
                    nextButton
                } else {
                    Button(tr("Проверить", "Verificar", "Check"), action: submit)
                        .buttonStyle(.chunky)
                        .frame(maxWidth: .infinity)
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("drill.check")
                }
            }
            .modifier(CardSurface(emphasized: isChecked))
            .onAppear {
                if mode == .dictation, let spoken = item.spoken { SpeechService.shared.speak(spoken) }
                focused = true
            }
            .id(item.id)
        }
    }

    private func verdict(_ check: AnswerCheck, item: DrillItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(check.verdict == .wrong ? tr("Не то", "Não é isso", "Not quite")
                                          : tr("Верно", "Certo", "Right"),
                  systemImage: check.verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.app(.headline))
                .foregroundStyle(check.verdict == .wrong ? Theme.red : Theme.green)
            if let hint = check.hint {
                Text(hint).font(.app(.callout)).foregroundStyle(Theme.muted)
            }
            if check.verdict == .wrong || check.verdict == .typo {
                HStack {
                    Text(item.answer).font(.app(.body, weight: .bold)).foregroundStyle(Theme.ink)
                    SpeakButton(text: item.answer, compact: true)
                }
            }
        }
    }

    private var nextButton: some View {
        Button(index + 1 < items.count ? tr("Дальше", "Seguinte", "Next") : tr("Итог", "Resultado", "Results")) {
            withAnimation(.app) {
                index += 1
                typed = ""
                check = nil
                dictation = nil
            }
        }
        .buttonStyle(.chunky)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("drill.next")
    }

    private func submit() {
        guard let item, !isChecked,
              !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        focused = false
        if mode == .dictation {
            let result = DictationCheck.check(typed: typed, expected: item.answer)
            dictation = result
            points += result.score
            if result.isPerfect { Haptics.success() } else { Haptics.warning() }
        } else {
            let result = AnswerChecker.check(input: typed, expected: item.answer, synonyms: item.synonyms)
            check = result
            switch result.verdict {
            case .correct: points += 1
            case .typo: points += 0.5
            case .wrong: break
            }
            if result.verdict == .wrong { Haptics.warning() } else { Haptics.success() }
        }
    }

    private func restart() {
        items = LessonDrill.items(notes: notes, mode: mode).shuffled()
        index = 0
        points = 0
        accepted = []
        typed = ""
        check = nil
        dictation = nil
    }
}

/// Слова диктанта с пометками: что верно, где ударение, что пропущено.
private struct DictationWords: View {
    let result: DictationResult
    let expected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.marked(result))
                .font(.app(.body))
            Text(expected)
                .font(.app(.callout, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    static func marked(_ result: DictationResult) -> AttributedString {
        var line = AttributedString()
        for word in result.words {
            var piece: AttributedString
            switch word.mark {
            case .correct:
                piece = AttributedString(word.typed ?? "")
                piece.foregroundColor = Theme.green
            case .accent, .typo:
                piece = AttributedString(word.expected ?? "")
                piece.foregroundColor = Theme.orange
                piece.underlineStyle = .single
            case .wrong:
                var typed = AttributedString(word.typed ?? "")
                typed.foregroundColor = Theme.red
                typed.strikethroughStyle = .single
                var right = AttributedString(" " + (word.expected ?? ""))
                right.foregroundColor = Theme.ink
                right.inlinePresentationIntent = .stronglyEmphasized
                piece = typed + right
            case .missing:
                piece = AttributedString("[" + (word.expected ?? "") + "]")
                piece.foregroundColor = Theme.red
                piece.inlinePresentationIntent = .stronglyEmphasized
            case .extra:
                piece = AttributedString(word.typed ?? "")
                piece.foregroundColor = Theme.muted
                piece.strikethroughStyle = .single
            }
            line += piece + AttributedString(" ")
        }
        return line
    }
}

/// Итог тренажёра: сколько верно и «ещё раз».
struct DrillSummary: View {
    let points: Double
    let total: Int
    var again: () -> Void

    private var share: Double { total == 0 ? 0 : points / Double(total) }

    var body: some View {
        VStack(spacing: 16) {
            MascotSays(mood: share >= 0.8 ? .cheer : .hello,
                       text: share >= 0.8
                           ? tr("Отлично! Слова урока уже твои.", "Ótimo! As palavras da aula já são tuas.",
                                "Great! The lesson's words are yours.")
                           : tr("Хорошая тренировка. Ещё круг — и будет легче.",
                                "Bom treino. Mais uma volta e fica mais fácil.",
                                "Good practice. One more round and it gets easier."))
            Text("\(Int((share * 100).rounded()))%")
                .font(.app(.largeTitle, weight: .heavy))
                .foregroundStyle(share >= 0.8 ? Theme.green : Theme.ink)
                .accessibilityIdentifier("drill.score")
            Button(tr("Ещё раз", "Outra vez", "Again"), action: again)
                .buttonStyle(.chunkySecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        NavigationStack {
            LessonDrillView(notes: PreviewData.lessonNotes, mode: .translation)
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#Preview("Пропуски") { NavigationStack { LessonDrillView(notes: PreviewData.lessonNotes, mode: .cloze) }.previewEnvironment() }
#endif
