import SwiftUI
import Observation
import AJFMCore

/// Панель вкладок в стиле iOS 26: капсула из «жидкого стекла», выбранная
/// вкладка — цветная подложка, которая перетекает к новой вкладке.
///
/// Панель стоит под содержимым, а не поверх него: когда она плавала над
/// экраном, нижние кнопки на части экранов уезжали под неё.
///
/// Своя панель, а не системный TabView: системный держит живыми все пять
/// вкладок, и каждое сохранение в базе перерисовывало скрытые экраны —
/// телефон грелся (см. RootView).
struct AppTabBar: View {
    @Binding var selection: AppTab

    @Namespace private var selectionSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Счётчик нажатий по вкладкам: значок подпрыгивает только у той,
    /// на которую перешли, а не у обеих.
    @State private var bounces: [AppTab: Int] = [:]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { item in
                button(for: item)
            }
        }
        .padding(5)
        // Не `.interactive()`: интерактивное стекло вспыхивает под пальцем
        // на всю ширину, и каждое нажатие выглядело как мигание.
        .glassEffect(.regular, in: .capsule)
        // Анимируется только подложка в самой панели. Смена экрана — без
        // анимации: внутри анимации экран вкладки проявлялся через
        // прозрачность, и это тоже мигало.
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8), value: selection)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func button(for item: AppTab) -> some View {
        let selected = item == selection
        return Button {
            guard !selected else { return }
            Haptics.tap()
            bounces[item, default: 0] += 1
            selection = item
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

/// Прячет панель вкладок, пока идёт сессия повторения. Общий объект, а не
/// preference: из экрана, открытого внутри NavigationStack, preference до
/// корня доходит не всегда.
@Observable
@MainActor
final class TabBarVisibility {
    static let shared = TabBarVisibility()
    var hiddenBySession = false
}
