import SwiftUI
import SwiftData
import AJFMCore

/// Карта уроков (P-69): шаг — урок, в порядке, в котором их добавляли.
/// Урок пройден, когда начаты все его слова и сдан мини-тест.
struct LessonsMapView: View {
    @Environment(\.modelContext) private var context
    @State private var path = LessonPath(steps: [])
    @State private var decks: [String: Deck] = [:]
    @State private var showLessonRequest = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if path.steps.isEmpty {
                    MascotSays(mood: .cards,
                               text: tr("Здесь будут твои уроки. Вставь конспект занятия или сфотографируй "
                                            + "страницу — сделаю карточки и тренажёры.",
                                        "Aqui vão ficar as tuas aulas. Cola o resumo ou fotografa a página "
                                            + "— faço cartões e treinos.",
                                        "Your lessons will live here. Paste your notes or snap the page — "
                                            + "I'll make cards and trainers."))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(tr("Пройдено \(path.doneCount) из \(path.total)",
                            "Concluídas \(path.doneCount) de \(path.total)",
                            "\(path.doneCount) of \(path.total) done"))
                        .font(.app(.headline))
                        .foregroundStyle(Theme.muted)
                    ForEach(Array(path.steps.enumerated()), id: \.element.id) { index, step in
                        if let deck = decks[step.id] {
                            NavigationLink {
                                LessonHubView(deck: deck)
                            } label: {
                                LessonNode(step: step, number: index + 1,
                                           isCurrent: step.id == path.current?.id)
                            }
                            .buttonStyle(.plain)
                            .offset(x: Self.offset(index))
                            .accessibilityIdentifier("lessons.step.\(index)")
                        }
                    }
                }

                Button {
                    showLessonRequest = true
                } label: {
                    Label(tr("Добавить урок", "Adicionar aula", "Add a lesson"), systemImage: "plus")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.chunky)
                .padding(.top, 8)
                .accessibilityIdentifier("lessons.add")
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("Мои уроки", "As minhas aulas", "My lessons"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(isPresented: $showLessonRequest, onDismiss: load) {
            DeckRequestView(lessonMode: true)
        }
    }

    private func load() {
        let all = LessonLibrary.decks(in: context)
        decks = Dictionary(all.map { (LessonLibrary.key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        path = LessonPath(steps: all.map(LessonLibrary.step(for:)))
    }

    /// Змейка, как у карты сериала: шаги не в столбик, а дорожкой.
    static func offset(_ index: Int) -> CGFloat {
        [0, 36, 0, -36][index % 4]
    }
}

/// Шаг карты: кружок с заполнением и название урока.
private struct LessonNode: View {
    let step: LessonStep
    let number: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: step.fraction)
                    .stroke(step.isDone ? Theme.green : Theme.purple,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if step.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.green)
                } else {
                    Text("\(number)")
                        .font(.app(.title3, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: 56, height: 56)
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    MascotView(mood: .hello, size: 30)
                        .offset(x: 12, y: -14)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.name)
                    .font(.app(.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(status)
                    .font(.app(.caption))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel(border: isCurrent ? Theme.purple : Theme.border)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isCurrent ? tr("Текущий урок", "Aula atual", "Current lesson") : "")
    }

    private var status: String {
        let words = "\(step.startedWords)/\(step.totalWords)"
        let quiz = step.bestQuiz.map {
            tr("тест \(Int(($0 * 100).rounded()))%", "teste \(Int(($0 * 100).rounded()))%",
               "quiz \(Int(($0 * 100).rounded()))%")
        } ?? tr("тест не пройден", "teste por fazer", "no quiz yet")
        return tr("Слова \(words) · ", "Palavras \(words) · ", "Words \(words) · ") + quiz
    }
}
