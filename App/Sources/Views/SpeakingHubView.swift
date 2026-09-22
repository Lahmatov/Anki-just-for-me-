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
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Пересказать серию")
                                Text("Наговори, о чём была серия, — разберём "
                                     + "понимание и язык")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "text.bubble")
                        }
                    }

                    NavigationLink {
                        MinimalPairsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Минимальные пары")
                                Text("ship или sheep — единственная честная "
                                     + "проверка произношения без облака")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "waveform")
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
