import SwiftUI
import UIKit

/// Системная шторка «Поделиться» — ею файл кладётся в Файлы, iCloud Drive
/// или отправляется куда угодно ещё.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
