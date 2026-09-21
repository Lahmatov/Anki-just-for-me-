import SwiftUI
import UIKit

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
                            Text("Вставь сюда JSON набора")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding()
            .navigationTitle("Вставить набор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Из буфера") {
                        text = UIPasteboard.general.string ?? text
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Разобрать") {
                        dismiss()
                        onSubmit(text)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
