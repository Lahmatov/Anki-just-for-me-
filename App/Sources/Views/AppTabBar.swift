import SwiftUI
import AJFMCore

/// Панель вкладок в стиле iOS 26: плавающая капсула из «жидкого стекла»
/// над содержимым, выбранная вкладка — цветная подложка, которая
/// перетекает к новой вкладке, а не появляется в ней заново.
///
/// Своя панель, а не системный TabView: системный держит живыми все пять
/// вкладок, и каждое сохранение в базе перерисовывало скрытые экраны —
/// телефон грелся (см. RootView).
struct AppTabBar: View {
    @Binding var selection: AppTab

    @Namespace private var selectionSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Счётчик нажатий по вкладкам: значок подпрыгивает только у той,
    /// на которую перешли. Раньше эффект был привязан к «выбрана ли» и
    /// срабатывал у обеих — и у новой, и у покинутой.
    @State private var bounces: [AppTab: Int] = [:]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { item in
                button(for: item)
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    private func button(for item: AppTab) -> some View {
        let selected = item == selection
        return Button {
            guard !selected else { return }
            Haptics.tap()
            bounces[item, default: 0] += 1
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15)
                                       : .spring(response: 0.36, dampingFraction: 0.8)) {
                selection = item
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .bold))
                    .symbolEffect(.bounce.up.byLayer, options: .speed(1.3),
                                  value: bounces[item, default: 0])
                Text(item.title)
                    .font(.app(.caption2, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(selected ? Theme.primary : Theme.ink.opacity(0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.primary.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: selectionSpace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("tab.\(item)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
