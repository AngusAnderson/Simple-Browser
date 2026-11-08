import AppKit
import Foundation
import Observation
import WebKit

enum ConnectionState {
    case noPage
    case loading
    case encrypted
    case notFullyEncrypted
    case failed

    var label: String {
        switch self {
        case .noPage: "No page loaded"
        case .loading: "Loading"
        case .encrypted: "Connection encrypted—not a website safety rating"
        case .notFullyEncrypted: "Connection is not fully encrypted"
        case .failed: "Navigation failed"
        }
    }

    var symbol: String {
        switch self {
        case .noPage: "globe"
        case .loading: "arrow.triangle.2.circlepath"
        case .encrypted: "lock"
        case .notFullyEncrypted: "exclamationmark.triangle"
        case .failed: "exclamationmark.circle"
        }
    }
}

@MainActor @Observable final class BrowserSession: NSObject {
    let id = UUID()
    let isPrivate: Bool

    @ObservationIgnored let webView: WKWebView

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    @ObservationIgnored private var isActive = true
    
    @ObservationIgnored var onPageFinished: ((BrowserSession) -> Void)?

    private(set) var committedURL: URL?
    private(set) var title = "Browser"
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var connection: ConnectionState = .noPage

    var errorMessage: String?

    init(
        isPrivate: Bool,
        dataStore: WKWebsiteDataStore
    ) {
        self.isPrivate = isPrivate

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        installObservations()
    }

    func load(_ url: URL) {
        guard isActive else { return }

        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        errorMessage = nil
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
    }

    func shutdown() {
        isActive = false
        onPageFinished = nil

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        observations.forEach { $0.invalidate() }
        observations.removeAll()
    }

    private func installObservations() {
        observations = [
            watch(\.estimatedProgress),
            watch(\.isLoading),
            watch(\.canGoBack),
            watch(\.canGoForward),
            watch(\.url),
            watch(\.title),
            watch(\.hasOnlySecureContent)
        ]
    }

    private func watch<Value>(
        _ keyPath: KeyPath<WKWebView, Value>
    ) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.refreshState()
            }
        }
    }

    private func refreshState() {
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        title = webView.title ?? committedURL?.host ?? "Browser"

        if committedURL != nil && !isLoading {
            committedURL = webView.url
        }

        if !isLoading, errorMessage == nil {
            updateConnection()
        }
    }

    private func updateConnection() {
        guard let url = committedURL else {
            connection = .noPage
            return
        }

        if url.scheme?.lowercased() == "https",
           webView.hasOnlySecureContent {
            connection = .encrypted
        } else {
            connection = .notFullyEncrypted
        }
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            refreshState()
            return
        }

        errorMessage = error.localizedDescription
        connection = .failed
        refreshState()
    }

    private func dialogTitle(for frame: WKFrameInfo) -> String {
        "Website dialog — \(frame.request.url?.host ?? "Unknown origin")"
    }
}

extension BrowserSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        errorMessage = nil
        connection = .loading
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        didCommit navigation: WKNavigation!
    ) {
        committedURL = webView.url
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        committedURL = webView.url
        refreshState()
        updateConnection()

        onPageFinished?(self)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "The webpage process stopped. Reload to try again."
        connection = .failed
        isLoading = false
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard isActive,
              let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)

            if navigationAction.navigationType == .linkActivated {
                webView.load(navigationAction.request)
            }

            return
        }

        switch NavigationPolicy.decision(for: url) {
        case .allow:
            decisionHandler(.allow)

        case .confirmHTTP:
            guard navigationAction.targetFrame?.isMainFrame == true else {
                decisionHandler(.cancel)
                return
            }

            let allowed = NativeDialogs.confirm(
                title: "Open an unencrypted page?",
                message: """
                \(url.absoluteString)

                This connection is not protected by HTTPS.
                Network policy may still prevent the page from loading.
                """,
                accept: "Continue"
            )

            decisionHandler(allowed ? .allow : .cancel)

        case .confirmExternalApplication:
            decisionHandler(.cancel)

            guard navigationAction.navigationType == .linkActivated else {
                return
            }

            let allowed = NativeDialogs.confirm(
                title: "Open another application?",
                message: url.absoluteString,
                accept: "Open Application"
            )

            if allowed {
                NSWorkspace.shared.open(url)
            }

        case .block:
            decisionHandler(.cancel)

            if navigationAction.targetFrame?.isMainFrame == true {
                errorMessage = "This type of navigation is not supported."
            }
        }
    }
}

extension BrowserSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        NativeDialogs.message(
            title: dialogTitle(for: frame),
            message: message
        )
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let accepted = NativeDialogs.confirm(
            title: dialogTitle(for: frame),
            message: message,
            accept: "OK"
        )
        completionHandler(accepted)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let result = NativeDialogs.prompt(
            title: dialogTitle(for: frame),
            message: prompt,
            defaultText: defaultText
        )
        completionHandler(result)
    }
}
