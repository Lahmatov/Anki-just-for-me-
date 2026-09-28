import SwiftUI
import AJFMCore

/// Тест словаря: слово на экране — «знаю» или «не знаю».
///
/// Одно слово за раз и две большие кнопки: тест проходят за три минуты
/// одним пальцем. Среди слов есть выдуманные, и об этом говорится заранее —
/// честность ответов важнее скорости.
struct PlacementTestView: View {
    var onFinish: (CEFRLevel) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var items = PlacementTest.items(seed: UInt64.random(in: 1...UInt64.max))
    @State private var index = 0
    @State private var answers: [String: Bool] = [:]
    @State private var started = false
    @State private var result: PlacementTest.Result?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    resultView(result)
                } else if started {
                    questionView
                } else {
                    introView
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Retro.background)
            .navigationTitle(tr("Тест словаря", "Teste de vocabulário", "Vocabulary test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.close) { dismiss() }
                }
            }
        }
    }

    // MARK: - Вступление

    private var introView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            IconBadge(systemName: "text.magnifyingglass", color: .indigo, size: 56)
            Text(tr("Знаешь это слово?", "Conheces esta palavra?", "Do you know this word?"))
                .font(.app(.largeTitle, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                let count = Counted.words(items.count)
                point("hand.tap", tr("Покажу \(count) по одному. Отвечай сразу, не раздумывая.",
                                     "Vou mostrar \(count), uma de cada vez. "
                                        + "Responde logo, sem pensar muito.",
                                     "I'll show \(count) one at a time. "
                                        + "Answer right away, without overthinking."))
                point("questionmark.diamond",
                      tr("Часть слов выдумана. Если ответишь «знаю» на выдумку, результат "
                            + "поправится вниз — так тест остаётся честным.",
                         "Algumas palavras são inventadas. Se disseres «sei» a uma inventada, "
                            + "o resultado desce — é assim que o teste se mantém honesto.",
                         "Some words are made up. Say “I know” to a made-up one and the "
                            + "result is adjusted down — that's how the test stays honest."))
                point("clock", tr("Около трёх минут. Уровень потом можно поменять руками.",
                                  "Cerca de três minutos. Depois podes mudar o nível à mão.",
                                  "About three minutes. You can change the level by hand later."))
            }
            Spacer()
            primaryButton(tr("Начать", "Começar", "Start")) {
                withAnimation(.snappy) { started = true }
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.app(.callout))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Вопрос

    private var questionView: some View {
        VStack(spacing: 24) {
            RetroProgressBar(value: Double(index), total: Double(items.count))
                .tint(.accentColor)

            Spacer()

            Text(items[index].word)
                .font(.app(.largeTitle, weight: .bold))
                .contentTransition(.opacity)
                .id(index)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))

            Spacer()

            Group {
                HStack(spacing: 12) {
                    Button {
                        answer(false)
                    } label: {
                        Text(tr("Не знаю", "Não sei", "Don't know"))
                            .font(.app(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.retroSecondary)

                    Button {
                        answer(true)
                    } label: {
                        Text(tr("Знаю", "Sei", "I know"))
                            .font(.app(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.retro)
                }
                .controlSize(.large)
            }

            Text("\(index + 1) " + tr("из", "de", "of") + " \(items.count)")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func answer(_ known: Bool) {
        Haptics.tap()
        answers[items[index].word] = known
        if index + 1 < items.count {
            withAnimation(.snappy) { index += 1 }
        } else {
            let scored = PlacementTest.score(answers)
            Log.info(
                .app, "Тест словаря пройден",
                detail: "оценка: \(scored.estimatedWords), уровень: \(scored.level.rawValue), "
                    + String(format: "выдумки: %.0f%%", scored.falseAlarmRate * 100))
            withAnimation(.snappy) { result = scored }
            Haptics.success()
        }
    }

    // MARK: - Итог

    private func resultView(_ result: PlacementTest.Result) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text(result.level.rawValue)
                .font(.display(.largeTitle))
                .scaleEffect(1.8)
                .padding(.bottom, 16)
            Text("≈ \(result.estimatedWords) "
                 + tr("самых частых слов из сериалов", "das palavras mais frequentes das séries",
                      "of the most common words in TV shows"))
                .font(.app(.headline))
                .multilineTextAlignment(.center)
            Text(tr("Наборы будут подбираться на ступень выше — "
                        + "уже не очевидные, но ещё часто встречающиеся слова.",
                    "Os baralhos vão ficar um degrau acima — palavras já não óbvias, "
                        + "mas ainda frequentes.",
                    "Decks will be picked one step above — words that are no longer "
                        + "obvious but still common."))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !result.isReliable {
                Label(
                    tr("На выдуманные слова часто отвечалось «знаю» — оценка может "
                            + "быть неточной. Можно пройти ещё раз.",
                       "Muitas palavras inventadas tiveram «sei» — a estimativa pode "
                            + "não ser exata. Podes repetir o teste.",
                       "Many made-up words got “I know” — the estimate may be off. "
                            + "You can take the test again."),
                    systemImage: "exclamationmark.triangle")
                    .font(.app(.footnote))
                    .foregroundStyle(.orange)
                    .padding()
                    .pixelFrame(fill: Color.orange.opacity(0.15), border: .orange, shadow: nil)
            }

            Spacer()

            primaryButton(tr("Сохранить уровень", "Guardar o nível", "Save the level")) {
                onFinish(result.level)
                dismiss()
            }
            Button(tr("Пройти ещё раз", "Repetir o teste", "Take it again")) { restart() }
                .font(.app(.callout))
        }
    }

    private func restart() {
        withAnimation(.snappy) {
            items = PlacementTest.items(seed: UInt64.random(in: 1...UInt64.max))
            answers = [:]
            index = 0
            result = nil
            started = true
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(.headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.retro)
        .controlSize(.large)
    }
}
