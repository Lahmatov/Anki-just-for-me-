import Foundation

/// Когда попросить оценить приложение (практика из открытых приложений с
/// высокими оценками): только сразу после удачного момента и только у тех,
/// кто уже вошёл во вкус. Просьба посреди ошибок даёт одну звезду; просьба
/// в первый день — пустую. iOS сама показывает окно не чаще трёх раз в год,
/// но и три раза — много, поэтому свой предел строже.
public struct ReviewPromptState: Codable, Equatable, Sendable {
    public var firstLaunch: Date
    public var lastAsked: Date?
    /// Версии, в которых уже просили: одна просьба на версию.
    public var askedVersions: [String]

    public init(firstLaunch: Date, lastAsked: Date? = nil, askedVersions: [String] = []) {
        self.firstLaunch = firstLaunch
        self.lastAsked = lastAsked
        self.askedVersions = askedVersions
    }
}

public enum ReviewPrompt {
    /// Удачный момент — то, после чего человеку хорошо.
    public enum Moment: String, Sendable {
        case perfectSession, dailyGoal, quizPassed, streakMilestone
    }

    public static let minimumStudyDays = 5
    public static let minimumAgeDays = 7
    public static let pauseDays = 120

    public static func shouldAsk(now: Date, state: ReviewPromptState, appVersion: String,
                                 studyDays: Int, moment: Moment?) -> Bool {
        guard moment != nil, studyDays >= minimumStudyDays else { return false }
        guard now.timeIntervalSince(state.firstLaunch) >= Double(minimumAgeDays) * 86_400 else { return false }
        guard !state.askedVersions.contains(appVersion) else { return false }
        if let last = state.lastAsked, now.timeIntervalSince(last) < Double(pauseDays) * 86_400 { return false }
        return true
    }

    /// Состояние после просьбы — помним дату и версию.
    public static func asked(_ state: ReviewPromptState, now: Date, appVersion: String) -> ReviewPromptState {
        var next = state
        next.lastAsked = now
        if !next.askedVersions.contains(appVersion) { next.askedVersions.append(appVersion) }
        return next
    }
}
