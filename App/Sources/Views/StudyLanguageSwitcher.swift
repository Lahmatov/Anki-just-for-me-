import SwiftUI
import AJFMCore

/// Какой язык учим: флаг в шапке «Сегодня» и строка в настройках (P-67).
///
/// Переключение открывает базу выбранного языка; прежняя остаётся как
/// была — вернёшься, и наборы, серия и карта на месте.
struct StudyLanguageMenu: View {
    private var store: StudyLanguageStore { .shared }

    var body: some View {
        Menu {
            Picker(tr("Изучаю", "Estou a aprender", "Learning"), selection: selection) {
                ForEach(StudyLanguage.allCases) { language in
                    Text("\(language.flag) \(language.nativeName)").tag(language)
                }
            }
        } label: {
            Text(store.current.flag)
                .font(.system(size: 28))
                .padding(6)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .accessibilityLabel(tr("Изучаемый язык", "Idioma que estudo", "Language I'm learning"))
        .accessibilityValue(store.current.nativeName)
        .accessibilityIdentifier("studyLanguage.menu")
    }

    private var selection: Binding<StudyLanguage> {
        Binding(get: { store.current }, set: { language in
            Haptics.tap()
            store.switchTo(language)
        })
    }
}

/// Строка выбора в настройках.
struct StudyLanguagePicker: View {
    private var store: StudyLanguageStore { .shared }

    var body: some View {
        Picker(tr("Изучаю", "Estou a aprender", "I'm learning"), selection: Binding(
            get: { store.current },
            set: { store.switchTo($0) })
        ) {
            ForEach(StudyLanguage.allCases) { language in
                Text("\(language.flag) \(language.nativeName)").tag(language)
            }
        }
        .accessibilityIdentifier("studyLanguage.picker")
    }
}

#if DEBUG
private struct Previews: View {
    var body: some View {
        List {
            StudyLanguagePicker()
        }
        .previewEnvironment()
    }
}

#Preview("Светлая") { Previews() }
#Preview("Тёмная") { Previews().preferredColorScheme(.dark) }
#Preview("Крупный шрифт") { Previews().dynamicTypeSize(.accessibility3) }
#endif
