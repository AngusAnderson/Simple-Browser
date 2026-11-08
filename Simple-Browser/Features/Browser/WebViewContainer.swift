import SwiftUI
import WebKit

@MainActor
struct WebViewContainer: NSViewRepresentable {
    let isPrivate: Bool
    let onCreate: (WKWebView) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        configuration.websiteDataStore = isPrivate
            ? .nonPersistent()
            : .default()

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.allowsBackForwardNavigationGestures = true

        DispatchQueue.main.async {
            onCreate(webView)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Bwah
    }
}
