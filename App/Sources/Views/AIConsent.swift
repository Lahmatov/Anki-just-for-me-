import SwiftUI
import AJFMCore

/// Согласие на отправку текста в Anthropic.
///
/// Правило App Store 5.1.2(i): прежде чем отдать данные человека сторонней
/// ИИ-службе, приложение должно прямо сказать, что и кому уходит, и получить
/// разрешение. Спрашивается один раз, перед первым запросом; отозвать можно
/// в «Настройки → Конфиденциальность».
enum AIConsent {
    static var isGiven: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.aiConsent) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.aiConsent) }
    }

    static var message: String {
        tr("Чтобы подобрать слова или разобрать пересказ, текст запроса, субтитры, текст "
                + "пересказа и список уже известных слов уйдут в Anthropic (Claude) — по твоему "
                + "ключу API. Anthropic не использует эти данные для обучения моделей. "
                + "Больше ничего не отправляется.",
           "Para escolher palavras ou analisar um reconto, o pedido, as legendas, o texto do "
                + "reconto e a lista de palavras conhecidas são enviados à Anthropic (Claude) — "
                + "com a tua chave da API. A Anthropic não usa estes dados para treinar modelos. "
                + "Nada mais é enviado.",
           "To pick words or review a retelling, your request, subtitles, the retelling text and "
                + "the list of known words are sent to Anthropic (Claude) using your API key. "
                + "Anthropic doesn't use this data to train models. Nothing else is sent.")
    }
}

private struct AIConsentAlert: ViewModifier {
    @Binding var pending: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            tr("Отправить в Claude?", "Enviar ao Claude?", "Send to Claude?"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button(tr("Разрешить", "Permitir", "Allow")) {
                AIConsent.isGiven = true
                let action = pending
                pending = nil
                action?()
            }
            Button(CommonText.cancel, role: .cancel) { pending = nil }
        } message: {
            Text(AIConsent.message)
        }
    }
}

extension View {
    /// Спрашивает согласие, когда в `pending` появляется действие, и выполняет
    /// его после «Разрешить». Экран кладёт туда действие через `AIConsent.run`.
    func aiConsentAlert(pending: Binding<(() -> Void)?>) -> some View {
        modifier(AIConsentAlert(pending: pending))
    }
}

extension AIConsent {
    /// Выполняет действие сразу, если согласие уже есть, иначе откладывает
    /// его до ответа в алерте.
    @MainActor
    static func run(_ action: @escaping () -> Void, pending: Binding<(() -> Void)?>) {
        if isGiven { action() } else { pending.wrappedValue = action }
    }
}
