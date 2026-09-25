import SwiftUI

/// Раздел устной практики: пересказ серии и тренажёр произношения.
struct SpeakingHubView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RetellView()
                    } label: {
                        HStack(spacing: 14) {
                            IconBadge(systemName: "text.bubble.fill", color: .purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Пересказать серию")
                                    .font(.app(.body, weight: .medium))
                                Text("Наговори, о чём была серия, — разберём "
                                     + "понимание и язык")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        MinimalPairsView()
                    } label: {
                        HStack(spacing: 14) {
                            IconBadge(systemName: "waveform", color: .pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Минимальные пары")
                                    .font(.app(.body, weight: .medium))
                                Text("ship или sheep — единственная честная "
                                     + "проверка произношения без облака")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Карточки тренируют узнавание слов, а говорение — "
                         + "то, ради чего язык и учат.")
                }
            }
            .navigationTitle("Речь")
        }
    }
}
