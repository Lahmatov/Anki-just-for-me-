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
                    tr("Проблемных нет", "Sem problemas", "No trouble"),
                    systemImage: "checkmark.circle",
                    description: Text(
                        tr("Ни одна карточка не провалилась ", "Nenhum cartão falhou ",
                           "No card has failed ")
                        + Counted.times(threshold) + ". "
                        + tr("Это хорошая новость.", "É uma boa notícia.", "That's good news.")))
            } else {
                Section {
                    Stepper(tr("Порог: ", "Limite: ", "Threshold: ")
                                + trCount(threshold, ru: ("провал", "провала", "провалов"),
                                          pt: ("falha", "falhas"), en: ("lapse", "lapses")),
                            value: $threshold, in: 3...15)
                } footer: {
                    Text(tr("Карточка попадает сюда, когда её забыли столько раз подряд.",
                            "Um cartão vem para aqui quando é esquecido tantas vezes.",
                            "A card lands here once it's been forgotten this many times."))
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
        .navigationTitle(tr("Трудные", "Difíceis", "Difficult"))
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
