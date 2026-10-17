import SwiftUI
import SwiftData
import AJFMCore

/// Урок (P-69): карточки по расписанию, тренажёры, мини-тест и речь —
/// всё на словах одного урока.
struct LessonHubView: View {
    let deck: Deck

    @State private var step: LessonStep?
    @State private var notes: [NoteData] = []

    private var language: StudyLanguage { StudyLanguageStore.storedCurrent }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                CardSectionHeader(title: tr("Учить", "Aprender", "Learn"))
                CardLink(title: tr("Карточки урока", "Cartões da aula", "Lesson cards"),
                         subtitle: tr("Повторения по расписанию", "Revisões no tempo certo",
                                      "Spaced reviews"),
                         systemImage: "rectangle.stack.fill", color: Theme.primary,
                         route: .review(deck: deck.persistentModelID))
                .accessibilityIdentifier("lesson.review")

                CardSectionHeader(title: tr("Тренажёры", "Treinos", "Trainers"))
                ForEach(LessonDrill.availableModes(notes: notes)) { mode in
                    CardLink(title: mode.title, subtitle: Self.subtitle(mode),
                             systemImage: Self.symbol(mode), color: Self.color(mode),
                             route: .lessonDrill(deck.persistentModelID, mode))
                    .accessibilityIdentifier("lesson.drill.\(mode.rawValue)")
                }
                let verbs = ConjugationDrill.verbs(notes: notes, language: language)
                if !verbs.isEmpty {
                    CardLink(title: tr("Спряжение", "Conjugação", "Conjugation"),
                             subtitle: Counted.words(verbs.count) + " · "
                                + Tense.allCases.map { $0.title(for: language) }.joined(separator: ", "),
                             systemImage: "list.bullet.indent", color: Theme.orange,
                             route: .conjugation(verbs: verbs))
                    .accessibilityIdentifier("lesson.conjugation")
                }

                CardSectionHeader(title: tr("Проверка", "Verificação", "Check"))
                CardLink(title: tr("Мини-тест", "Mini-teste", "Mini quiz"),
                         subtitle: quizSubtitle,
                         systemImage: "checkmark.seal.fill", color: Theme.green,
                         route: .lessonQuiz(deck.persistentModelID))
                .accessibilityIdentifier("lesson.quiz")

                CardSectionHeader(title: tr("Речь", "Fala", "Speaking"))
                CardLink(title: tr("Расскажи об уроке", "Fala sobre a aula", "Talk about the lesson"),
                         subtitle: tr("Скажи вслух — посчитаю, какие слова урока прозвучали",
                                      "Diz em voz alta — conto as palavras da aula que usaste",
                                      "Say it out loud — I'll count the lesson words you used"),
                         systemImage: "mic.fill", color: Theme.red,
                         route: .lessonSpeak(deck.persistentModelID))
                .accessibilityIdentifier("lesson.speak")
                CardLink(title: tr("Разговор с Мончиком", "Conversa com o Monchik", "Chat with Monchik"),
                         subtitle: tr("Вопросы, на которые отвечаешь словами урока",
                                      "Perguntas para responder com as palavras da aula",
                                      "Questions you answer with the lesson's words"),
                         systemImage: "bubble.left.and.bubble.right.fill", color: Theme.blue,
                         route: .lessonChat(deck.persistentModelID))
                .accessibilityIdentifier("lesson.chat")
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notes = LessonLibrary.notes(of: deck)
            step = LessonLibrary.step(for: deck)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let step {
            VStack(alignment: .leading, spacing: 8) {
                Text(deck.name)
                    .font(.app(.title2, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                ChunkyProgressBar(value: step.fraction, tint: step.isDone ? Theme.green : Theme.purple)
                Text(step.isDone
                     ? tr("Урок пройден — повторяй карточки, чтобы не забыть.",
                          "Aula concluída — revê os cartões para não esquecer.",
                          "Lesson done — keep reviewing so it sticks.")
                     : tr("Начато слов: \(step.startedWords) из \(step.totalWords). Пройти урок — "
                            + "начать все слова и сдать мини-тест на 80%.",
                          "Palavras começadas: \(step.startedWords) de \(step.totalWords). Para concluir — "
                            + "começar todas e passar o mini-teste com 80%.",
                          "Words started: \(step.startedWords) of \(step.totalWords). To finish — start "
                            + "them all and pass the mini quiz with 80%."))
                    .font(.app(.callout))
                    .foregroundStyle(Theme.muted)
            }
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
    }

    private var quizSubtitle: String {
        guard let best = step?.bestQuiz else {
            return tr("Десять вопросов, зачёт — 80%", "Dez perguntas, passa com 80%",
                      "Ten questions, pass mark 80%")
        }
        let percent = Int((best * 100).rounded())
        return tr("Лучший результат: \(percent)%", "Melhor resultado: \(percent)%", "Best score: \(percent)%")
    }

    static func subtitle(_ mode: DrillMode) -> String {
        switch mode {
        case .translation: return tr("Видишь перевод — пишешь слово или фразу",
                                     "Vês a tradução — escreves a palavra",
                                     "See the translation — type the word")
        case .cloze: return tr("Впиши слово в пример", "Completa o exemplo", "Fill the gap in the example")
        case .dictation: return tr("Слушаешь фразу — записываешь", "Ouves a frase — escreves",
                                   "Listen and write it down")
        case .pronunciation: return tr("Скажи вслух — проверю", "Diz em voz alta — eu verifico",
                                       "Say it out loud — I'll check")
        }
    }

    static func symbol(_ mode: DrillMode) -> String {
        switch mode {
        case .translation: return "character.book.closed.fill"
        case .cloze: return "text.insert"
        case .dictation: return "ear.fill"
        case .pronunciation: return "waveform"
        }
    }

    static func color(_ mode: DrillMode) -> Color {
        switch mode {
        case .translation: return Theme.primary
        case .cloze: return Theme.blue
        case .dictation: return Theme.purple
        case .pronunciation: return Theme.red
        }
    }
}

/// О чём разговор с Мончиком об уроке: название и слова.
struct LessonTopic: Equatable, Hashable {
    var title: String
    var terms: [String]

    init(title: String, terms: [String]) {
        self.title = title
        self.terms = terms
    }

    @MainActor
    init(deck: Deck, notes: [NoteData]) {
        self.init(title: deck.name, terms: notes.map(\.term))
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        RoutedStack {
            LessonHubView(deck: PreviewData.lessonDeck)
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#endif
