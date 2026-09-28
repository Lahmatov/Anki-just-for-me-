import Foundation

/// Ход теста уровня: карточки словаря, затем вопросы грамматики.
///
/// Вынесен из экрана, потому что правил много и все влияют на оценку:
/// что засчитывается «знаю», что происходит с выдумкой, куда ведёт «назад».
/// Экран только показывает состояние и зовёт методы.
///
/// Карточка словаря:
/// - «Не знаю» — слово незнакомо, сразу следующая карточка.
/// - «Знаю» — карточка переворачивается. У настоящего слова на обороте
///   значение, и человек сам отмечает, угадал ли; «не угадал» считается
///   как «не знаю». У выдумки на обороте «такого слова нет», и ответ
///   сразу идёт в ложные тревоги.
/// «Назад» отменяет последний шаг: с оборота — на лицевую сторону той же
/// карточки, с лицевой — на предыдущую карточку с отменой её ответа.
public struct PlacementSession: Equatable, Sendable {

    public enum Stage: Equatable, Sendable {
        /// Карточка словаря; `revealed` — перевёрнута ли.
        case card(index: Int, revealed: Bool)
        case grammar(index: Int)
        case finished
    }

    public let items: [PlacementTest.Item]
    public let questions: [GrammarTest.Question]
    public let seed: UInt64
    public private(set) var stage: Stage
    /// Слово → знакомо ли (после самопроверки).
    public private(set) var vocabularyAnswers: [String: Bool] = [:]
    /// Номер вопроса → верно ли.
    public private(set) var grammarAnswers: [Int: Bool] = [:]
    public private(set) var skippedGrammar = false

    public init(seed: UInt64, questions: [GrammarTest.Question] = GrammarTest.questions) {
        self.seed = seed
        self.items = PlacementTest.items(seed: seed)
        self.questions = questions
        self.stage = items.isEmpty ? .finished : .card(index: 0, revealed: false)
    }

    // MARK: - Текущее состояние

    public var currentItem: PlacementTest.Item? {
        if case .card(let index, _) = stage { return items[index] }
        return nil
    }

    public var currentQuestion: GrammarTest.Question? {
        if case .grammar(let index) = stage { return questions[index] }
        return nil
    }

    public var currentOptions: [String] {
        currentQuestion.map { GrammarTest.shuffledOptions(of: $0, seed: seed) } ?? []
    }

    /// Шагов всего и пройдено — для полосы прогресса.
    public var totalSteps: Int { items.count + (skippedGrammar ? 0 : questions.count) }

    public var completedSteps: Int {
        switch stage {
        case .card(let index, _): return index
        case .grammar(let index): return items.count + index
        case .finished: return totalSteps
        }
    }

    public var canGoBack: Bool {
        switch stage {
        case .card(let index, let revealed): return index > 0 || revealed
        case .grammar: return true
        case .finished: return false
        }
    }

    // MARK: - Карточки

    /// Ответ на лицевой стороне.
    public mutating func claim(known: Bool) {
        guard case .card(let index, false) = stage else { return }
        let item = items[index]
        if known {
            // Выдумка засчитывается ложной тревогой сразу: проверять на
            // обороте нечего. Настоящее слово ждёт самопроверки.
            if !item.isReal { vocabularyAnswers[item.word] = true }
            stage = .card(index: index, revealed: true)
        } else {
            vocabularyAnswers[item.word] = false
            advanceCard(from: index)
        }
    }

    /// Самопроверка на обороте настоящего слова.
    public mutating func confirm(understood: Bool) {
        guard case .card(let index, true) = stage, items[index].isReal else { return }
        vocabularyAnswers[items[index].word] = understood
        advanceCard(from: index)
    }

    /// «Дальше» на обороте выдумки.
    public mutating func next() {
        guard case .card(let index, true) = stage, !items[index].isReal else { return }
        advanceCard(from: index)
    }

    private mutating func advanceCard(from index: Int) {
        if index + 1 < items.count {
            stage = .card(index: index + 1, revealed: false)
        } else {
            stage = questions.isEmpty ? .finished : .grammar(index: 0)
        }
    }

    // MARK: - Грамматика

    public mutating func answer(_ option: String) {
        guard case .grammar(let index) = stage else { return }
        let question = questions[index]
        grammarAnswers[question.id] = option == question.answer
        stage = index + 1 < questions.count ? .grammar(index: index + 1) : .finished
    }

    /// Грамматику можно пропустить — тогда итог только по словарю.
    public mutating func skipGrammar() {
        guard case .grammar = stage else { return }
        grammarAnswers = [:]
        skippedGrammar = true
        stage = .finished
    }

    // MARK: - Назад

    public mutating func goBack() {
        switch stage {
        case .card(let index, true):
            // Перевернул по ошибке — вернуть лицевую сторону. Ложная
            // тревога на выдумке при этом тоже отменяется.
            vocabularyAnswers[items[index].word] = nil
            stage = .card(index: index, revealed: false)
        case .card(let index, false):
            guard index > 0 else { return }
            vocabularyAnswers[items[index - 1].word] = nil
            stage = .card(index: index - 1, revealed: false)
        case .grammar(let index):
            if index > 0 {
                grammarAnswers[questions[index - 1].id] = nil
                stage = .grammar(index: index - 1)
            } else if let last = items.indices.last {
                vocabularyAnswers[items[last].word] = nil
                stage = .card(index: last, revealed: false)
            }
        case .finished:
            break
        }
    }

    // MARK: - Итог

    public struct Outcome: Equatable, Sendable {
        public var vocabulary: PlacementTest.Result
        /// nil — грамматику пропустили.
        public var grammar: CEFRLevel?
        public var level: CEFRLevel
    }

    public var outcome: Outcome {
        let vocabulary = PlacementTest.score(vocabularyAnswers)
        let grammar = skippedGrammar || grammarAnswers.isEmpty
            ? nil : GrammarTest.level(answers: grammarAnswers)
        return Outcome(
            vocabulary: vocabulary, grammar: grammar,
            level: GrammarTest.combined(vocabulary: vocabulary.level, grammar: grammar))
    }
}
