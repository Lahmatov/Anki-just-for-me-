import WidgetKit
import SwiftUI
import AJFMCore

/// Виджет «Recap»: сколько карточек ждёт, огонёк серии и Мончик.
///
/// Виджет не открывает базу — он читает снимок, который приложение
/// оставляет в общей группе (WidgetBridge). Нет группы или снимка —
/// приглашает открыть приложение, не выдумывая цифр.
struct RecapEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetSnapshot.Presentation
}

struct RecapProvider: TimelineProvider {
    private var snapshot: WidgetSnapshot? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RecapAppGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$("),
              let defaults = UserDefaults(suiteName: group) else { return nil }
        let snapshot = WidgetSnapshot.decode(defaults.data(forKey: WidgetSnapshot.defaultsKey))
        if let language = snapshot.flatMap({ AppLanguage(rawValue: $0.language) }) {
            Loc.language = language
        }
        return snapshot
    }

    func placeholder(in context: Context) -> RecapEntry {
        RecapEntry(date: Date(), presentation: .today(due: 12, streak: 5, studied: false, goal: 0.4))
    }

    func getSnapshot(in context: Context, completion: @escaping (RecapEntry) -> Void) {
        let current = snapshot
        completion(RecapEntry(
            date: Date(),
            presentation: context.isPreview && current == nil
                ? placeholder(in: context).presentation
                : WidgetSnapshot.presentation(of: current, now: Date())))
    }

    /// Две записи: сейчас и начало следующего учебного дня — тогда цифры
    /// устаревают, и виджет сам переходит к «загляни».
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecapEntry>) -> Void) {
        let current = snapshot
        let now = Date()
        let boundary = WidgetSnapshot.nextRefresh(after: now, cutoffHour: current?.cutoffHour ?? 4)
        let entries = [
            RecapEntry(date: now, presentation: WidgetSnapshot.presentation(of: current, now: now)),
            RecapEntry(date: boundary, presentation: WidgetSnapshot.presentation(of: current, now: boundary)),
        ]
        completion(Timeline(entries: entries, policy: .after(boundary.addingTimeInterval(3_600))))
    }
}

struct RecapWidgetView: View {
    let entry: RecapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: - Формы

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(mascot).resizable().scaledToFit().frame(width: 44, height: 44)
                Spacer(minLength: 0)
                streakBadge
            }
            Spacer(minLength: 0)
            headline.font(.system(size: 34, weight: .heavy, design: .rounded))
            caption.font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color("WidgetMuted"))
                .lineLimit(2)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            Image(mascot).resizable().scaledToFit().frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                headline.font(.system(size: 40, weight: .heavy, design: .rounded))
                caption.font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("WidgetMuted"))
                    .lineLimit(2)
                if case .today(_, _, _, let goal) = entry.presentation {
                    ProgressView(value: goal)
                        .tint(Color("WidgetPrimary"))
                        .accessibilityLabel(tr("Цель дня", "Objetivo do dia", "Daily goal"))
                }
            }
            Spacer(minLength: 0)
            streakBadge
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if case .today(let due, _, _, _) = entry.presentation {
                    Text("\(due)").font(.system(size: 20, weight: .heavy, design: .rounded))
                } else {
                    Image(systemName: "rectangle.stack.fill")
                }
                Image(systemName: "flame.fill").font(.system(size: 10))
            }
        }
    }

    // MARK: - Части

    private var mascot: String {
        switch entry.presentation {
        case .today(let due, _, let studied, _) where due == 0 || studied: return "WidgetMascotCheer"
        case .empty: return "WidgetMascotSleepy"
        default: return "WidgetMascotHello"
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch entry.presentation {
        case .today(let due, _, _, _):
            Text(due == 0 ? "✓" : "\(due)")
                .foregroundStyle(Color("WidgetInk"))
                .contentTransition(.numericText())
        case .newDay, .empty:
            Text("Recap").foregroundStyle(Color("WidgetInk"))
        }
    }

    private var caption: Text {
        switch entry.presentation {
        case .today(let due, _, _, _) where due == 0:
            return Text(tr("На сегодня всё", "Por hoje é tudo", "All done today"))
        case .today(let due, _, _, _):
            return Text(trForm(due, ru: ("карточка ждёт", "карточки ждут", "карточек ждут"),
                               pt: ("cartão à espera", "cartões à espera"),
                               en: ("card waiting", "cards waiting")))
        case .newDay(_, let atRisk):
            return Text(atRisk
                        ? tr("Новый день — не дай серии прерваться", "Novo dia — não deixes a série parar",
                             "New day — keep the streak going")
                        : tr("Карточки уже ждут", "Os cartões já estão à espera", "Your cards are waiting"))
        case .empty:
            return Text(tr("Открой Recap, чтобы здесь появились карточки",
                           "Abre o Recap para os cartões aparecerem aqui",
                           "Open Recap to see your cards here"))
        }
    }

    @ViewBuilder
    private var streakBadge: some View {
        let streak: Int = {
            switch entry.presentation {
            case .today(_, let streak, _, _), .newDay(let streak, _): return streak
            case .empty: return 0
            }
        }()
        if streak > 0 {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(streak)").font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color("WidgetInk"))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Counted.days(streak))
        }
    }
}

struct RecapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecapWidget", provider: RecapProvider()) { entry in
            RecapWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Recap")
        .description(Text(tr("Сколько карточек ждёт и серия дней.", "Cartões à espera e a série de dias.",
                             "Cards waiting and your streak.")))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct RecapWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecapWidget()
        SessionLiveActivity()
    }
}
