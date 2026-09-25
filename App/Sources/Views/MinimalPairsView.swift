import SwiftUI
import AJFMCore

/// Тренажёр минимальных пар — единственный способ честно проверить
/// произношение без облачного разбора.
///
/// Обычное распознавание бесполезно как проверка: оно подгоняет услышанное
/// под словарь. Но когда два слова различаются ровно одним звуком, выбор
/// распознавателя становится настоящим сигналом.
struct MinimalPairsView: View {
    @State private var pairIndex = 0
    @State private var targetIsFirst = true
    @State private var lastVerdict: PronunciationAssessment.Verdict?
    @State private var streak = 0

    private var pairs: [MinimalPair] { MinimalPairLibrary.all }
    private var pair: MinimalPair { pairs[pairIndex % pairs.count] }
    private var target: String { targetIsFirst ? pair.first : pair.second }

    var body: some View {
        List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Произнеси", "Diz", "Say"))
                            .font(.app(.caption)).foregroundStyle(.secondary)
                        Text(target).font(.app(.largeTitle, weight: .bold))
                        Text(pair.contrast).font(.app(.callout)).foregroundStyle(.secondary)

                        PronunciationRecorderView(word: target, pair: pair) { assessment in
                            lastVerdict = assessment.verdict
                            streak = assessment.verdict == .matched ? streak + 1 : 0
                            ProgressService.recordPronunciationStreak(streak)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text(pair.hint).font(.app(.callout))
                    HStack {
                        SpeakButton(text: pair.first, label: pair.first)
                        SpeakButton(text: pair.second, label: pair.second)
                    }
                } header: {
                    Text(tr("Как различать", "Como distinguir", "How to tell them apart"))
                } footer: {
                    Text(tr("Послушай оба слова подряд — разница слышна лучше, "
                                + "чем в каждом по отдельности.",
                            "Ouve as duas palavras seguidas — a diferença nota-se melhor "
                                + "do que em cada uma sozinha.",
                            "Listen to both words back to back — the difference is easier "
                                + "to hear than in each one alone."))
                }

                Section {
                    Button(tr("Другое слово из пары", "A outra palavra do par",
                              "The other word of the pair")) {
                        targetIsFirst.toggle()
                        lastVerdict = nil
                    }
                    Button(tr("Следующая пара", "Próximo par", "Next pair")) {
                        pairIndex += 1
                        targetIsFirst = Bool.random()
                        lastVerdict = nil
                    }
                } footer: {
                    if streak > 0 {
                        Text(tr("Подряд верно: ", "Certas seguidas: ", "Correct in a row: ")
                             + "\(streak)")
                    }
                }

                Section {
                    ForEach(pairs) { item in
                        HStack {
                            Text("\(item.first) — \(item.second)")
                            Spacer()
                            Text(item.contrast)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let index = pairs.firstIndex(of: item) {
                                pairIndex = index
                                targetIsFirst = true
                                lastVerdict = nil
                            }
                        }
                    }
                } header: {
                    Text(tr("Все пары", "Todos os pares", "All pairs"))
                } footer: {
                    Text(tr("Подобраны под типичные трудности русскоязычных: межзубные, "
                                + "различение долгих и кратких гласных, /v/ против /w/.",
                            "Escolhidos para as dificuldades típicas de quem fala português: "
                                + "sons interdentais, vogais longas e curtas, /æ/ e /ʌ/.",
                            "Chosen for the typical trouble spots of non-native speakers: "
                                + "the “th” sounds, long vs short vowels, /v/ vs /w/."))
                }
        }
        .navigationTitle(tr("Произношение", "Pronúncia", "Pronunciation"))
    }
}
