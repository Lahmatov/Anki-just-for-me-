import Foundation
import SwiftData
import Observation
import AJFMCore

struct SessionStats: Equatable {
    var answered = 0
    var correct = 0
    var typos = 0
    var wrong = 0

    var accuracy: Double {
        answered == 0 ? 0 : Double(correct + typos) / Double(answered)
    }
}

/// Состояние одной сессии повторений.
@Observable
@MainActor
final class ReviewSessionModel {
    private(set) var cards: [Card] = []
    private(set) var index = 0
    private(set) var isRevealed = false
    private(set) var check: AnswerCheck?
    private(set) var choices: [String] = []
    private(set) var stats = SessionStats()
    private(set) var intervals: [Grade: TimeInterval] = [:]
    var typedAnswer = ""

    private let service: ReviewService
    private let context: ModelContext
    private var shownAt = Date()
    /// Переводы других слов — из них берутся неправильные варианты ответа.
    private var distractorPool: [String] = []

    init(context: ModelContext, settings: AppSettings = AppSettings.load()) {
        self.context = context
        self.service = ReviewService(context: context, settings: settings)
    }

    var current: Card? {
        index < cards.count ? cards[index] : nil
    }

    var isFinished: Bool { index >= cards.count }

    var progress: Double {
        cards.isEmpty ? 1 : Double(index) / Double(cards.count)
    }

    // MARK: - Загрузка

    func load(deck: Deck? = nil, now: Date = Date()) {
        let queue: ReviewQueue
        if let deck {
            queue = service.queue(for: deck, now: now)
        } else {
            queue = (try? service.todayQueue(now: now)) ?? ReviewQueue(
                cards: [], summary: QueueSummary(learning: 0, review: 0, new: 0, heldBack: 0))
        }

        let all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let byID = Dictionary(
            all.map { (ReviewService.queueCard(from: $0).id, $0) },
            uniquingKeysWith: { first, _ in first })

        cards = queue.cards.compactMap { byID[$0.id] }
        distractorPool = ((try? context.fetch(FetchDescriptor<Note>())) ?? [])
            .map(\.translation)
            .filter { !$0.isEmpty }

        index = 0
        stats = SessionStats()
        prepareCurrent()
    }

    // MARK: - Ход сессии

    private func prepareCurrent() {
        isRevealed = false
        check = nil
        typedAnswer = ""
        shownAt = Date()
        choices = []
        intervals = [:]

        guard let card = current else { return }
        intervals = service.preview(for: card)
        if card.type == .recognition {
            choices = makeChoices(for: card)
        }
    }

    /// Варианты для карточки на узнавание: правильный перевод плюс три чужих.
    private func makeChoices(for card: Card) -> [String] {
        guard let correct = card.note?.translation else { return [] }
        var pool = Set(distractorPool)
        pool.remove(correct)
        let wrong = pool.shuffled().prefix(3)
        // Меньше четырёх слов в базе — покажем сколько есть, это не повод падать.
        return ([correct] + wrong).shuffled()
    }

    /// Показать ответ. Для карточек с вводом сначала сверяем напечатанное.
    func reveal() {
        guard let card = current, !isRevealed else { return }

        if card.type.requiresTyping, let note = card.note {
            let result = AnswerChecker.check(
                input: typedAnswer,
                expected: note.term,
                synonyms: note.synonyms,
                strict: card.type == .spelling)
            check = result
            stats.answered += 1
            switch result.verdict {
            case .correct: stats.correct += 1
            case .typo: stats.typos += 1
            case .wrong: stats.wrong += 1
            }
        }
        isRevealed = true
    }

    /// Выбор варианта на карточке узнавания — сразу и ответ, и показ результата.
    func choose(_ option: String) {
        guard let card = current, !isRevealed else { return }
        let correct = card.note?.translation ?? ""
        let isCorrect = option == correct
        check = AnswerCheck(
            verdict: isCorrect ? .correct : .wrong,
            matched: correct,
            hint: isCorrect ? nil : "Правильно: «\(correct)»")
        stats.answered += 1
        if isCorrect { stats.correct += 1 } else { stats.wrong += 1 }
        isRevealed = true
    }

    func grade(_ grade: Grade) {
        guard let card = current else { return }
        try? service.apply(
            grade: grade, to: card, timeSpent: Date().timeIntervalSince(shownAt))
        index += 1
        prepareCurrent()
    }

    /// Оценка, которую стоит предложить по результату проверки ввода.
    var suggestedGrade: Grade? {
        switch check?.verdict {
        case .correct: return .good
        case .typo: return .hard
        case .wrong: return .again
        case nil: return nil
        }
    }

    func interval(for grade: Grade) -> String {
        IntervalFormatter.short(intervals[grade] ?? 0)
    }
}

extension CardType {
    /// Типы, где ответ нужно напечатать — их проверяет AnswerChecker.
    var requiresTyping: Bool {
        switch self {
        case .recall, .listening, .spelling, .cloze: return true
        case .recognition, .pronunciation: return false
        }
    }

    /// Что делать пользователю — подпись над карточкой.
    var instruction: String {
        switch self {
        case .recognition: return "Выбери перевод"
        case .recall: return "Напиши по-английски"
        case .listening: return "Запиши то, что слышишь"
        case .spelling: return "Напиши слово без ошибок"
        case .pronunciation: return "Произнеси вслух"
        case .cloze: return "Вставь пропущенное слово"
        }
    }
}
