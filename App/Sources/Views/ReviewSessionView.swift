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
            ProgressView(value: model.progress)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let card = model.current {
                        CardPromptView(card: card, model: model)
                    }
                }
                .padding()
            }

            Divider()
            footer(model)
        }
    }

    @ViewBuilder
    private func footer(_ model: ReviewSessionModel) -> some View {
        VStack(spacing: 12) {
            if model.isRevealed {
                GradeButtons(model: model)
            } else if model.current?.type.requiresTyping == true {
                Button("Проверить") { model.reveal() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else if model.current?.type == .pronunciation {
                Button("Показать") { model.reveal() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            Text("\(model.index + 1) из \(model.cards.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct CardPromptView: View {
    let card: Card
    let model: ReviewSessionModel

    private var note: Note? { card.note }

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
    }

    @ViewBuilder
    private var prompt: some View {
        switch card.type {
        case .recognition:
            Text(note?.term ?? "").font(.largeTitle).bold()
        case .recall:
            Text(note?.translation ?? "").font(.title).bold()
        case .cloze:
            Text(note?.cloze ?? note?.example ?? note?.translation ?? "")
                .font(.title2)
        case .listening, .spelling:
            VStack(alignment: .leading, spacing: 8) {
                // Звук появится в следующей итерации — пока карточка работает
                // как обычный ввод по переводу, чтобы прогресс не стоял.
                Label("Звук появится в следующей итерации", systemImage: "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(note?.translation ?? "").font(.title).bold()
            }
        case .pronunciation:
            VStack(alignment: .leading, spacing: 8) {
                Text(note?.term ?? "").font(.largeTitle).bold()
                if let ipa = note?.ipa, !ipa.isEmpty {
                    Text(ipa).foregroundStyle(.secondary)
                }
                Text("Произнеси вслух, потом оцени себя сам.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var choices: some View {
        VStack(spacing: 8) {
            ForEach(model.choices, id: \.self) { option in
                Button {
                    model.choose(option)
                } label: {
                    Text(option)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
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
                if let hint = check.hint {
                    Text(hint).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Divider()

            Text(note?.term ?? "").font(.title2).bold()
            if let ipa = note?.ipa, !ipa.isEmpty {
                Text(ipa).foregroundStyle(.secondary)
            }
            Text(note?.translation ?? "").font(.body)

            if let example = note?.example, !example.isEmpty {
                Text(example).font(.callout).italic().padding(.top, 4)
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases, id: \.rawValue) { grade in
                Button {
                    model.grade(grade)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.title).font(.callout)
                        // Интервал прямо на кнопке: выбор оценки должен быть
                        // осознанным, а не гаданием.
                        Text(model.interval(for: grade))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(model.suggestedGrade == grade ? .accentColor : nil)
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

            Button("Готово", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
