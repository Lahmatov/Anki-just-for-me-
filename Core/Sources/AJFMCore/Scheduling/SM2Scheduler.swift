import Foundation

/// SM-2 — классика SuperMemo 1987 года, на которой Anki прожил десятилетия.
///
/// Проще FSRS и полностью предсказуем: интервал умножается на коэффициент
/// лёгкости, который сам ползёт вверх-вниз от оценок. Держим как альтернативу —
/// когда хочется понимать, почему карточка пришла именно сегодня.
public struct SM2Scheduler: Scheduler {
    public let id: SchedulerID = .sm2

    public static let defaultEase: Double = 2.5
    public static let minimumEase: Double = 1.3

    public var learningSteps: [TimeInterval]
    public var relearningSteps: [TimeInterval]
    /// Интервал после выпуска из фазы заучивания.
    public var graduatingIntervalDays: Double
    /// Интервал, если выпустить карточку сразу оценкой «Легко».
    public var easyIntervalDays: Double
    public var maximumIntervalDays: Double

    public init(
        learningSteps: [TimeInterval] = [60, 600],
        relearningSteps: [TimeInterval] = [600],
        graduatingIntervalDays: Double = 1,
        easyIntervalDays: Double = 4,
        maximumIntervalDays: Double = 36_500
    ) {
        self.learningSteps = learningSteps.isEmpty ? [60, 600] : learningSteps
        self.relearningSteps = relearningSteps.isEmpty ? [600] : relearningSteps
        self.graduatingIntervalDays = graduatingIntervalDays
        self.easyIntervalDays = easyIntervalDays
        self.maximumIntervalDays = maximumIntervalDays
    }

    public func review(_ state: ReviewState, grade: Grade, now: Date) -> ReviewState {
        var card = state
        card.ease = card.ease ?? Self.defaultEase
        let ease = card.ease ?? Self.defaultEase
        var intervalDays: Double

        switch card.state {
        case .new, .learning, .relearning:
            let steps = card.state == .relearning ? relearningSteps : learningSteps
            let currentStep = card.step ?? 0
            let fallback: LearningState = card.state == .relearning ? .relearning : .learning

            switch grade {
            case .again:
                card.state = fallback
                card.step = 0
                intervalDays = (steps.first ?? 60) / 86_400

            case .hard:
                card.state = fallback
                card.step = currentStep
                intervalDays = steps[min(currentStep, steps.count - 1)] / 86_400

            case .good:
                if currentStep + 1 >= steps.count {
                    card.state = .review
                    card.step = nil
                    intervalDays = graduatingIntervalDays
                } else {
                    card.state = fallback
                    card.step = currentStep + 1
                    intervalDays = steps[currentStep + 1] / 86_400
                }

            case .easy:
                card.state = .review
                card.step = nil
                intervalDays = easyIntervalDays
            }

        case .review:
            let previous = max(card.intervalDays, graduatingIntervalDays)
            switch grade {
            case .again:
                card.lapses += 1
                card.ease = max(Self.minimumEase, ease - 0.2)
                card.state = .relearning
                card.step = 0
                // Накопленный интервал сгорает: выйдя из переучивания, карточка
                // начнёт с graduatingIntervalDays — как в Anki при множителе 0.
                intervalDays = relearningSteps[0] / 86_400

            case .hard:
                card.ease = max(Self.minimumEase, ease - 0.15)
                intervalDays = previous * 1.2

            case .good:
                intervalDays = previous * ease

            case .easy:
                card.ease = ease + 0.15
                intervalDays = previous * ease * 1.3
            }
        }

        if card.state == .review {
            intervalDays = min(max(intervalDays, 1), maximumIntervalDays)
            // Интервалы в днях держим целыми — так повторения не расползаются
            // внутри суток и попадают в один учебный день.
            intervalDays = intervalDays.rounded()
        }

        card.due = now.addingTimeInterval(intervalDays * 86_400)
        card.lastReview = now
        card.intervalDays = intervalDays
        card.reps += 1
        return card
    }
}
