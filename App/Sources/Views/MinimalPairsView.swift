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

    private var pairs: [MinimalPair] { MinimalPairLibrary.forRussianSpeakers }
    private var pair: MinimalPair { pairs[pairIndex % pairs.count] }
    private var target: String { targetIsFirst ? pair.first : pair.second }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Произнеси").font(.caption).foregroundStyle(.secondary)
                        Text(target).font(.largeTitle).bold()
                        Text(pair.contrast).font(.callout).foregroundStyle(.secondary)

                        PronunciationRecorderView(word: target, pair: pair) { assessment in
                            lastVerdict = assessment.verdict
                            streak = assessment.verdict == .matched ? streak + 1 : 0
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text(pair.hint).font(.callout)
                    HStack {
                        SpeakButton(text: pair.first, label: pair.first)
                        SpeakButton(text: pair.second, label: pair.second)
                    }
                } header: {
                    Text("Как различать")
                } footer: {
                    Text("Послушай оба слова подряд — разница слышна лучше, "
                         + "чем в каждом по отдельности.")
                }

                Section {
                    Button("Другое слово из пары") {
                        targetIsFirst.toggle()
                        lastVerdict = nil
                    }
                    Button("Следующая пара") {
                        pairIndex += 1
                        targetIsFirst = Bool.random()
                        lastVerdict = nil
                    }
                } footer: {
                    if streak > 0 {
                        Text("Подряд верно: \(streak)")
                    }
                }

                Section {
                    ForEach(pairs) { item in
                        HStack {
                            Text("\(item.first) — \(item.second)")
                            Spacer()
                            Text(item.contrast)
                                .font(.caption)
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
                    Text("Все пары")
                } footer: {
                    Text("Подобраны под типичные трудности русскоязычных: межзубные, "
                         + "различение долгих и кратких гласных, /v/ против /w/.")
                }
            }
            .navigationTitle("Произношение")
        }
    }
}
