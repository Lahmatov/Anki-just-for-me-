import SwiftUI
import UIKit
import AJFMCore

/// Второй путь доставки набора: скопировал JSON прямо из чата — вставил сюда.
/// Работает, когда возиться с файлом лень.
struct PasteImportView: View {
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(tr("Вставь сюда JSON набора", "Cola aqui o JSON do baralho",
                                    "Paste the deck JSON here"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding()
            .navigationTitle(tr("Вставить набор", "Colar baralho", "Paste deck"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonText.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Из буфера", "Da área de transferência", "From clipboard")) {
                        text = UIPasteboard.general.string ?? text
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Разобрать", "Ler", "Parse")) {
                        dismiss()
                        onSubmit(text)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
