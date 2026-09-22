import Foundation

/// Лёгкое представление карточки для построения очереди.
/// Ядро не знает про базу — приложение конвертирует свои сущности в это.
public struct QueueCard: Equatable, Sendable, Identifiable {
    public var id: String
    /// Все карточки одного слова считаются «братьями» — см. burySiblings.
    public var noteID: String
    public var type: CardType
    public var state: LearningState
    public var due: Date
    public var intervalDays: Double
    /// Для стабильного порядка при равных сроках.
    public var addedAt: Date

    public init(
        id: String, noteID: String, type: CardType, state: LearningState,
        due: Date, intervalDays: Double = 0, addedAt: Date = .distantPast
    ) {
        self.id = id
        self.noteID = noteID
        self.type = type
        self.state = state
        self.due = due
        self.intervalDays = intervalDays
        self.addedAt = addedAt
    }
}

public struct QueueConfig: Equatable, Sendable {
    public var newPerDay: Int
    public var reviewsPerDay: Int
    /// Показав одну карточку слова, остальные его карточки откладываем на завтра.
    public var burySiblings: Bool
    /// Учебный день заканчивается не в полночь: вечерняя сессия за полночь —
    /// это всё ещё «сегодня», иначе ночные занятия рвут счёт дней.
    public var dayCutoffHour: Int

    public init(
        newPerDay: Int = 20,
        reviewsPerDay: Int = 200,
        burySiblings: Bool = true,
        dayCutoffHour: Int = 4
    ) {
        self.newPerDay = max(0, newPerDay)
        self.reviewsPerDay = max(0, reviewsPerDay)
        self.burySiblings = burySiblings
        self.dayCutoffHour = min(max(dayCutoffHour, 0), 23)
    }
}

public struct QueueSummary: Equatable, Sendable {
    public var learning: Int
    public var review: Int
    public var new: Int
    /// Отложено из-за лимитов и «захоронения» братьев.
    public var heldBack: Int

    public init(learning: Int, review: Int, new: Int, heldBack: Int) {
        self.learning = learning
        self.review = review
        self.new = new
        self.heldBack = heldBack
    }

    public var total: Int { learning + review + new }
    public var isEmpty: Bool { total == 0 }
}

public struct ReviewQueue: Equatable, Sendable {
    public var cards: [QueueCard]
    public var summary: QueueSummary

    public init(cards: [QueueCard], summary: QueueSummary) {
        self.cards = cards
        self.summary = summary
    }

    public var isEmpty: Bool { cards.isEmpty }
}

public enum ReviewQueueBuilder {

    /// Начало учебного дня для момента `date`: сегодня в `cutoffHour`, а если
    /// сейчас раньше этого часа — вчера.
    public static func studyDayStart(
        for date: Date, cutoffHour: Int, calendar: Calendar = .current
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = cutoffHour
        components.minute = 0
        components.second = 0
        let todayCutoff = calendar.date(from: components) ?? date
        guard date < todayCutoff else { return todayCutoff }
        // Календарём, а не вычитанием 86 400 секунд: в день перехода на летнее
        // время сутки длятся 23 или 25 часов, и ключи учебных дней разъезжались
        // бы с теми, что считают по календарю.
        return calendar.date(byAdding: .day, value: -1, to: todayCutoff)
            ?? todayCutoff.addingTimeInterval(-86_400)
    }

    public static func studyDayEnd(
        for date: Date, cutoffHour: Int, calendar: Calendar = .current
    ) -> Date {
        let start = studyDayStart(for: date, cutoffHour: cutoffHour, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
    }

    /// Очередь на текущий учебный день.
    ///
    /// Порядок продуман так: сперва карточки в заучивании, у которых уже подошёл
    /// срок (они «горят» и висят в рамках сессии), затем повторения вперемешку
    /// с новыми. Перемешивание не случайное, а равномерное — чтобы новые слова
    /// не свалились все в конец, когда внимание уже кончилось.
    public static func build(
        cards: [QueueCard],
        config: QueueConfig = QueueConfig(),
        now: Date,
        calendar: Calendar = .current
    ) -> ReviewQueue {
        let dayEnd = studyDayEnd(for: now, cutoffHour: config.dayCutoffHour, calendar: calendar)

        var learning: [QueueCard] = []
        var review: [QueueCard] = []
        var fresh: [QueueCard] = []
        var heldBack = 0

        for card in cards {
            switch card.state {
            case .new:
                fresh.append(card)
            case .learning, .relearning:
                // Шаги заучивания измеряются минутами, поэтому смотрим на текущий
                // момент, а не на конец дня.
                if card.due <= now { learning.append(card) } else { heldBack += 1 }
            case .review:
                if card.due < dayEnd { review.append(card) } else { heldBack += 1 }
            }
        }

        learning.sort(by: earlierFirst)
        review.sort(by: earlierFirst)
        fresh.sort { ($0.addedAt, $0.id) < ($1.addedAt, $1.id) }

        if review.count > config.reviewsPerDay {
            heldBack += review.count - config.reviewsPerDay
            review = Array(review.prefix(config.reviewsPerDay))
        }
        if fresh.count > config.newPerDay {
            heldBack += fresh.count - config.newPerDay
            fresh = Array(fresh.prefix(config.newPerDay))
        }

        var ordered = learning + interleave(review, fresh)

        if config.burySiblings {
            let before = ordered.count
            ordered = buryingSiblings(ordered)
            heldBack += before - ordered.count
        }

        return ReviewQueue(
            cards: ordered,
            summary: QueueSummary(
                learning: ordered.filter { $0.state == .learning || $0.state == .relearning }.count,
                review: ordered.filter { $0.state == .review }.count,
                new: ordered.filter { $0.state == .new }.count,
                heldBack: heldBack))
    }

    private static func earlierFirst(_ lhs: QueueCard, _ rhs: QueueCard) -> Bool {
        lhs.due == rhs.due ? lhs.id < rhs.id : lhs.due < rhs.due
    }

    /// Оставляет по одной карточке на слово. Без этого одно и то же слово
    /// встретится за сессию пять раз подряд — и ты решишь, что выучил его,
    /// хотя просто запомнил на минуту.
    static func buryingSiblings(_ cards: [QueueCard]) -> [QueueCard] {
        var seenNotes: Set<String> = []
        return cards.filter { seenNotes.insert($0.noteID).inserted }
    }

    /// Равномерно вплетает новые карточки в поток повторений.
    ///
    /// Новые слова требуют больше внимания, поэтому им заранее отводятся места
    /// в середине очереди: ни в самом начале (сперва надо разогреться на знакомом),
    /// ни в хвосте, где внимание уже кончилось.
    static func interleave(_ reviews: [QueueCard], _ fresh: [QueueCard]) -> [QueueCard] {
        guard !fresh.isEmpty else { return reviews }
        guard !reviews.isEmpty else { return fresh }

        let total = reviews.count + fresh.count
        let spacing = Double(total) / Double(fresh.count)
        // Середина каждого отрезка: при 2 новых на 10 карточек это места 2 и 7.
        var slots: Set<Int> = []
        for index in 0..<fresh.count {
            slots.insert(Int(((Double(index) + 0.5) * spacing).rounded(.down)))
        }

        var result: [QueueCard] = []
        result.reserveCapacity(total)
        var reviewIndex = 0
        var freshIndex = 0

        for position in 0..<total {
            if slots.contains(position), freshIndex < fresh.count {
                result.append(fresh[freshIndex])
                freshIndex += 1
            } else if reviewIndex < reviews.count {
                result.append(reviews[reviewIndex])
                reviewIndex += 1
            } else if freshIndex < fresh.count {
                result.append(fresh[freshIndex])
                freshIndex += 1
            }
        }
        return result
    }
}
