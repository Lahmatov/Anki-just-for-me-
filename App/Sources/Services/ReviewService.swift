import Foundation
import SwiftData
import AJFMCore

/// Сборка очереди на сегодня и применение оценок.
@MainActor
struct ReviewService {
    let context: ModelContext
    var config: QueueConfig
    var desiredRetention: Double

    init(
        context: ModelContext,
        settings: AppSettings = AppSettings.load()
    ) {
        self.context = context
        self.config = settings.queueConfig
        self.desiredRetention = settings.desiredRetention
    }

    init(context: ModelContext, config: QueueConfig, desiredRetention: Double = 0.9) {
        self.context = context
        self.config = config
        self.desiredRetention = desiredRetention
    }

    /// Очередь по всей базе.
    func todayQueue(now: Date = Date()) throws -> ReviewQueue {
        queue(from: try context.fetch(FetchDescriptor<Card>()), now: now)
    }

    /// Очередь по одному набору — когда хочется позаниматься конкретной серией.
    func queue(for deck: Deck, now: Date = Date()) -> ReviewQueue {
        queue(from: deck.notes.flatMap(\.cards), now: now)
    }

    private func queue(from cards: [Card], now: Date) -> ReviewQueue {
        ReviewQueueBuilder.build(
            cards: cards.map(Self.queueCard(from:)), config: config, now: now)
    }

    static func queueCard(from card: Card) -> QueueCard {
        QueueCard(
            id: card.persistentModelID.storageIdentifier,
            noteID: card.note?.persistentModelID.storageIdentifier ?? "",
            type: card.type,
            state: card.state,
            due: card.due,
            intervalDays: card.intervalDays,
            addedAt: card.createdAt)
    }

    /// Применяет оценку: двигает карточку по алгоритму её набора и пишет журнал.
    ///
    /// Журнал ведётся не для красоты — по нему считаются награды, и только
    /// честные повторы (сделанные в сессии) идут в зачёт.
    @discardableResult
    func apply(
        grade: Grade, to card: Card, timeSpent: TimeInterval = 0,
        isHonest: Bool = true, now: Date = Date()
    ) throws -> ReviewState {
        let schedulerID = card.note?.deck?.scheduler ?? .fsrs6
        let scheduler = SchedulerFactory.make(schedulerID, desiredRetention: desiredRetention)
        let next = scheduler.review(card.reviewState, grade: grade, now: now)
        card.reviewState = next

        let log = Review(
            card: card, grade: grade.rawValue, timeSpent: timeSpent,
            algorithm: schedulerID.rawValue, isHonest: isHonest)
        context.insert(log)
        log.card = card

        try context.save()
        return next
    }

    /// Что покажут кнопки оценок.
    ///
    /// Считается без разброса интервалов: иначе на кнопке было бы одно число,
    /// а по нажатию получалось другое — и подпись превращалась бы в обман.
    func preview(for card: Card, now: Date = Date()) -> [Grade: TimeInterval] {
        let schedulerID = card.note?.deck?.scheduler ?? .fsrs6
        let scheduler: any Scheduler = schedulerID == .fsrs6
            ? FSRS6Scheduler(desiredRetention: desiredRetention, enableFuzzing: false)
            : SchedulerFactory.make(schedulerID, desiredRetention: desiredRetention)
        return scheduler.preview(card.reviewState, now: now)
    }

    func card(withID id: String) throws -> Card? {
        try context.fetch(FetchDescriptor<Card>())
            .first { $0.persistentModelID.storageIdentifier == id }
    }
}

extension PersistentIdentifier {
    /// Стабильная строка для связи карточки из базы с элементом очереди в ядре.
    var storageIdentifier: String { String(describing: self) }
}
