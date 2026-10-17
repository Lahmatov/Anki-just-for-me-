import SwiftUI
import DeclaredAgeRange
import AJFMCore

/// Заслонка, когда закон требует проверку возраста (P-75): младше 13 —
/// Recap не для детей; возраст не передан — просим поделиться.
struct AgeGateView: View {
    let decision: AgeDecision
    @Environment(\.requestAgeRange) private var requestAgeRange
    private var service: AgeAssuranceService { .shared }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                if decision == .underMinimumAge {
                    MascotEmptyState(
                        mood: .sleepy,
                        title: tr("Recap — для тех, кому 13 и больше",
                                  "O Recap é para maiores de 13 anos",
                                  "Recap is for ages 13 and up"),
                        message: tr("Так требует закон и рейтинг приложения. Если возраст указан неверно, взрослый может исправить его в настройках Apple ID.",
                                    "Assim o exigem a lei e a classificação da app. Se a idade estiver errada, um adulto pode corrigi-la nas definições do Apple ID.",
                                    "The law and the app's age rating require this. If the age is wrong, an adult can fix it in Apple ID settings."))
                } else {
                    MascotEmptyState(
                        mood: .thinking,
                        title: tr("Нужен возраст", "É preciso a idade", "Age needed"),
                        message: tr("В вашем регионе закон требует, чтобы App Store сообщил приложению возрастную группу. Дата рождения к нам не попадает — только группа, например «18+».",
                                    "Na sua região, a lei exige que a App Store indique à app o escalão etário. A data de nascimento não nos chega — só o escalão, por exemplo «18+».",
                                    "In your region the law requires the App Store to tell the app your age group. We never see your birth date — only the group, such as \"18+\".")) {
                        Button {
                            Task { await service.checkIfNeeded(request: requestAgeRange, force: true) }
                        } label: {
                            Text(tr("Поделиться возрастом", "Partilhar idade", "Share age range"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.chunky)
                        .disabled(service.checking)
                        .padding(.top, 8)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("ageGate")
    }
}
