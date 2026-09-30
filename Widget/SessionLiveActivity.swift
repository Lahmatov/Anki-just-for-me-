import ActivityKit
import SwiftUI
import WidgetKit
import AJFMCore

/// Live Activity сессии: на экране блокировки и в Dynamic Island видно,
/// сколько карточек осталось и примерно сколько минут.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            lockScreen(context)
                .padding(16)
                .activityBackgroundTint(Color("WidgetBackground"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("WidgetMascotHello").resizable().scaledToFit().frame(width: 40, height: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.remaining)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress(context.state)).tint(Color("WidgetPrimary"))
                        Text(caption(context))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
            } compactLeading: {
                Image(systemName: "rectangle.stack.fill").foregroundStyle(Color("WidgetPrimary"))
            } compactTrailing: {
                Text("\(context.state.remaining)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
            } minimal: {
                Text("\(context.state.remaining)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image("WidgetMascotHello").resizable().scaledToFit().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.deckName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("WidgetMuted"))
                    .lineLimit(1)
                Text(caption(context))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color("WidgetInk"))
                ProgressView(value: progress(context.state)).tint(Color("WidgetPrimary"))
            }
        }
    }

    private func progress(_ state: SessionActivityAttributes.ContentState) -> Double {
        state.total > 0 ? Double(state.total - state.remaining) / Double(state.total) : 0
    }

    private func caption(_ context: ActivityViewContext<SessionActivityAttributes>) -> String {
        if let language = AppLanguage(rawValue: context.attributes.language) { Loc.language = language }
        let state = context.state
        let cards = trForm(state.remaining, ru: ("карточка", "карточки", "карточек"),
                           pt: ("cartão", "cartões"), en: ("card", "cards"))
        return "\(state.remaining) \(cards) · ≈ " + Counted.minutes(state.minutesLeft)
    }
}
