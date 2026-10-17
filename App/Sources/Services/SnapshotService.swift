import Foundation
import SwiftData
import AJFMCore

/// Ежедневный снимок прогресса.
@MainActor
enum SnapshotService {
    static func recordIfNeeded(context: ModelContext, now: Date = Date()) {
        let existing = (try? context.fetch(FetchDescriptor<ProgressSnapshot>())) ?? []
        let today = Calendar.current.startOfDay(for: now)
        guard !existing.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }) else { return }

        let progress = ProgressService(context: context)
        context.insert(ProgressSnapshot(
            date: today,
            matureWords: progress.matureWordCount(),
            totalWords: (try? context.fetch(FetchDescriptor<Note>()))?.count ?? 0))
        try? context.save()
    }
}
