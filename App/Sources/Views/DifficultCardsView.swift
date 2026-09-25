import SwiftUI
import SwiftData
import AJFMCore

/// Карточки, которые проваливаются снова и снова.
///
/// Смысл экрана — не «повторить их ещё раз», а починить: если слово забыто
/// восемь раз, девятый повтор ничего не изменит. Менять надо карточку.
struct DifficultCardsView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]

    @AppStorage(SettingsKey.leechThreshold) private var threshold = LeechPolicy.defaultThreshold

    private var difficult: [Card] {
        cards
            .filter { LeechPolicy.isLeech(lapses: $0.lapses, threshold: threshold) }
            .sorted {
                LeechPolicy.severity(lapses: $0.lapses, reps: $0.reps)
                    > LeechPolicy.severity(lapses: $1.lapses, reps: $1.reps)
            }
    }

    var body: some View {
        List {
            if difficult.isEmpty {
                ContentUnavailableView(
                    "Проблемных нет",
                    systemImage: "checkmark.circle",
                    description: Text(
                        "Ни одна карточка не провалилась "
                        + RussianPlural.phrase(threshold, one: "раз", few: "раза", many: "раз") + ". "
                        + "Это хорошая новость."))
            } else {
                Section {
                    Stepper("Порог: \(threshold) провалов", value: $threshold, in: 3...15)
                } footer: {
                    Text("Карточка попадает сюда, когда её забыли столько раз подряд.")
                }

                ForEach(difficult) { card in
                    Section {
                        NavigationLink {
                            if let note = card.note {
                                NoteDetailView(note: note)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.note?.term ?? "—").fontWeight(.medium)
                                Text(card.note?.translation ?? "")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(LeechPolicy.summary(lapses: card.lapses))
                                    Text("·")
                                    Text(card.type.title)
                                }
                                .font(.app(.caption2))
                                .foregroundStyle(.orange)
                            }
                        }

                        Text(advice(for: card))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Трудные")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func advice(for card: Card) -> String {
        LeechPolicy.advice(
            lapses: card.lapses,
            hasExample: !((card.note?.example ?? "").isEmpty),
            termWordCount: (card.note?.term ?? "")
                .split(whereSeparator: { $0.isWhitespace }).count)
    }
}
