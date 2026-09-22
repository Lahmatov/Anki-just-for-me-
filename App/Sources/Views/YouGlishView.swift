import SwiftUI
import WebKit

/// Видео-контекст: как слово звучит у живых людей.
///
/// Виджет YouGlish свободен для личного некоммерческого использования.
/// Для публикации в App Store потребовалось бы отдельное разрешение —
/// но приложение туда и не собирается, см. docs/vision.md.
struct YouGlishView: UIViewRepresentable {
    let word: String
    var accent: String = "us"

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let encoded = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard !encoded.isEmpty,
              let url = URL(string: "https://youglish.com/pronounce/\(encoded)/english/\(accent)")
        else { return }

        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

struct YouGlishScreen: View {
    let word: String

    var body: some View {
        YouGlishView(word: word)
            .navigationTitle(word)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: .bottom)
    }
}
