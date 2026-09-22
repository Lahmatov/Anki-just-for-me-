import SwiftUI
import AJFMCore

/// Кнопка озвучки. Вынесена отдельно, потому что встречается всюду:
/// в списке слов, в карточке, в ответе.
struct SpeakButton: View {
    let text: String
    var rate: SpeechRate = .normal
    var label: String?
    var compact = false

    private var speech: SpeechService { SpeechService.shared }

    var body: some View {
        Group {
            if compact {
                button.buttonStyle(.borderless)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var button: some View {
        Button {
            speech.speak(text, rate: rate)
        } label: {
            if let label {
                Label(label, systemImage: icon)
            } else {
                Image(systemName: icon)
            }
        }
    }

    private var icon: String {
        rate == .slow ? "tortoise" : "speaker.wave.2"
    }
}
