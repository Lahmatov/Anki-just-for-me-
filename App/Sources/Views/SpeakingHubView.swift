import SwiftUI
import AJFMCore

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
                                Text(tr("Пересказать серию", "Recontar um episódio", "Retell an episode"))
                                    .font(.app(.body, weight: .medium))
                                Text(tr("Наговори, о чём была серия, — разберём "
                                            + "понимание и язык",
                                        "Conta de que tratou o episódio — analisamos "
                                            + "a compreensão e a língua",
                                        "Say what the episode was about — we'll review "
                                            + "understanding and language"))
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
                                Text(tr("Минимальные пары", "Pares mínimos", "Minimal pairs"))
                                    .font(.app(.body, weight: .medium))
                                Text(tr("ship или sheep — единственная честная "
                                            + "проверка произношения без облака",
                                        "ship ou sheep — a única verificação honesta "
                                            + "da pronúncia sem a nuvem",
                                        "ship or sheep — the only honest pronunciation "
                                            + "check without the cloud"))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text(tr("Карточки тренируют узнавание слов, а говорение — "
                                + "то, ради чего язык и учат.",
                            "Os cartões treinam o reconhecimento das palavras, e falar é "
                                + "a razão por que se aprende uma língua.",
                            "Cards train recognizing words, and speaking is what you "
                                + "learn a language for."))
                }
            }
            .navigationTitle(tr("Речь", "Fala", "Speech"))
        }
    }
}
