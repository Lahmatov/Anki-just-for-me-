import SwiftUI
import AJFMCore

/// Панель вкладок в пиксельном стиле: сплошная полоса с толстой рамкой
/// сверху, выбранная вкладка — «нажатая» фиолетовая клетка.
struct RetroTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { item in
                button(for: item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            VStack(spacing: 0) {
                Rectangle().fill(Retro.ink).frame(height: Retro.pixel)
                Retro.surface
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
                    .font(.system(size: 18, weight: .bold))
                Text(item.title)
                    .font(.app(.caption2, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Retro.onPrimary : Retro.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    ZStack {
                        PixelRect(step: 2).fill(Retro.ink)
                        PixelRect(step: 2).fill(Retro.primary).padding(2)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
