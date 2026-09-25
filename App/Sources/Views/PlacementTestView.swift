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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Тест словаря")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    // MARK: - Вступление

    private var introView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            IconBadge(systemName: "text.magnifyingglass", color: .indigo, size: 56)
            Text("Знаешь это слово?")
                .font(.app(.largeTitle, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                point("hand.tap", "Покажу \(items.count) слов по одному. Отвечай сразу, "
                      + "не раздумывая.")
                point("questionmark.diamond", "Часть слов выдумана. Если ответишь «знаю» "
                      + "на выдумку, результат поправится вниз — так тест остаётся честным.")
                point("clock", "Около трёх минут. Уровень потом можно поменять руками.")
            }
            Spacer()
            primaryButton("Начать") {
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
            ProgressView(value: Double(index), total: Double(items.count))
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

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        answer(false)
                    } label: {
                        Text("Не знаю")
                            .font(.app(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)

                    Button {
                        answer(true)
                    } label: {
                        Text("Знаю")
                            .font(.app(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }

            Text("\(index + 1) из \(items.count)")
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
                .font(.app(.largeTitle, weight: .heavy))
                .scaleEffect(1.8)
                .padding(.bottom, 16)
            Text("≈ \(result.estimatedWords) самых частых слов из сериалов")
                .font(.app(.headline))
                .multilineTextAlignment(.center)
            Text("Наборы будут подбираться на ступень выше — "
                 + "уже не очевидные, но ещё часто встречающиеся слова.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !result.isReliable {
                Label(
                    "На выдуманные слова часто отвечалось «знаю» — оценка может "
                    + "быть неточной. Можно пройти ещё раз.",
                    systemImage: "exclamationmark.triangle")
                    .font(.app(.footnote))
                    .foregroundStyle(.orange)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.orange.opacity(0.1)))
            }

            Spacer()

            primaryButton("Сохранить уровень") {
                onFinish(result.level)
                dismiss()
            }
            Button("Пройти ещё раз") { restart() }
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
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}
