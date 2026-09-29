import SwiftUI
import AJFMCore

/// Аватарка профиля: фото, лось или инициалы на цветном круге.
struct AvatarView: View {
    var size: CGFloat = 56

    private var profile: ProfileStore { ProfileStore.shared }

    var body: some View {
        ZStack {
            switch profile.avatar {
            case .photo:
                if let photo = profile.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    initials
                }
            case .mascot(let mood):
                Theme.tint
                Image(mood.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            case .initials:
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.border, lineWidth: max(1.5, size * 0.03)))
        .accessibilityLabel(tr("Аватарка", "Avatar", "Avatar"))
    }

    @ViewBuilder
    private var initials: some View {
        let letters = profile.initials
        ZStack {
            Theme.primary
            if letters.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .bold))
            } else {
                Text(letters)
                    .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(Theme.onPrimary)
    }
}
