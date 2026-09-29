import SwiftUI
import AJFMCore

/// Панель вкладок в стиле обучающих приложений: белая полоса с тонкой
/// рамкой сверху, выбранная вкладка — цветной значок в светлой плашке
/// с рамкой главного цвета.
struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { item in
                button(for: item)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(height: Theme.stroke)
                Theme.surface
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func button(for item: AppTab) -> some View {
        let selected = item == selection
        return Button {
            guard !selected else { return }
            Haptics.tap()
            selection = item
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .symbolEffect(.bounce, value: selected)
                Text(item.title)
                    .font(.app(.caption2, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Theme.primary : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.tint)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.primary.opacity(0.6), lineWidth: Theme.stroke)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("tab.\(item)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
