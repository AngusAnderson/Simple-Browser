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
    
    @ObservationIgnored var onDownload: ((WKDownload) -> Void)?
    @ObservationIgnored var onOpenRequest: ((URLRequest, Bool) -> Void)?
    @ObservationIgnored var onCreateWebView: ((WKWebViewConfiguration, Bool) -> WKWebView?)?
    @ObservationIgnored var onCloseRequested: (() -> Void)?

    private(set) var committedURL: URL?
    private(set) var title = "Browser"
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var connection: ConnectionState = .noPage

    var errorMessage: String?

    convenience init(
        isPrivate: Bool,
        dataStore: WKWebsiteDataStore
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        
        self.init(
            isPrivate: isPrivate,
            configuration: configuration
        )
    }
    
    init(
        isPrivate: Bool,
        configuration: WKWebViewConfiguration
    ) {
        self.isPrivate = isPrivate
        
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
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
        
        onDownload = nil
        onOpenRequest = nil
        onCreateWebView = nil
        onCloseRequested = nil

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        observations.forEach { $0.invalidate() }
        observations.removeAll()
    }
    
    private func handOffDownload(_ download: WKDownload) {
        isLoading = false

        if let onDownload {
            onDownload(download)
        } else {
            download.cancel(nil)
            errorMessage = "The download manager is unavailable."
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
    
    private func installObservations() {
        observations = [
            webView.observe(
                \.estimatedProgress,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    
                    self.progress = self.webView.estimatedProgress
                }
            },
            
            webView.observe(
                \.isLoading,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    
                    self.progress = self.webView.estimatedProgress
                }
            },
            
            webView.observe(
                \.canGoBack,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    
                    self.canGoBack = self.webView.canGoBack
                }
            },
            
            webView.observe(
                \.canGoForward,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    
                    self.canGoForward = self.webView.canGoForward
                }
            },
            
            webView.observe(
                \.title,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    
                    self.title = self.webView.title ?? self.committedURL?.host ?? "Browser"
                }
            },
            
            webView.observe(
                \.url,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    
                    if !self.webView.isLoading,
                       self.committedURL != nil {
                        self.committedURL = self.webView.url
                        self.updateConnection()
                    }
                }
            },
            
            webView.observe(
                \.hasOnlySecureContent,
                 options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isActive,
                          !self.webView.isLoading,
                          self.errorMessage == nil else { return }
                    
                    self.updateConnection()
                }
            }
        ]
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
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard isActive else {
            decisionHandler(.cancel)
            return
        }

        if navigationResponse.isForMainFrame,
           !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        handOffDownload(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        handOffDownload(download)
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

        switch NavigationPolicy.decision(for: url) {
        case .allow:
            break

        case .confirmHTTP:
            let isTopLevel = navigationAction.targetFrame == nil
                || navigationAction.targetFrame?.isMainFrame == true

            guard isTopLevel else {
                decisionHandler(.cancel)
                return
            }

            let accepted = NativeDialogs.confirm(
                title: "Open an unencrypted page?",
                message: """
                \(url.absoluteString)

                This connection is not protected by HTTPS.
                Network policy may still prevent it from loading.
                """,
                accept: "Continue"
            )

            guard accepted else {
                decisionHandler(.cancel)
                return
            }

        case .confirmExternalApplication:
            decisionHandler(.cancel)

            guard navigationAction.navigationType == .linkActivated else {
                return
            }

            let accepted = NativeDialogs.confirm(
                title: "Open another application?",
                message: url.absoluteString,
                accept: "Open Application"
            )

            if accepted {
                NSWorkspace.shared.open(url)
            }

            return

        case .block:
            decisionHandler(.cancel)

            if navigationAction.targetFrame == nil
                || navigationAction.targetFrame?.isMainFrame == true {
                errorMessage = "This type of navigation is not supported."
            }

            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        if navigationAction.targetFrame == nil {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command) {
            decisionHandler(.cancel)

            onOpenRequest?(
                navigationAction.request,
                false
            )
            return
        }

        decisionHandler(.allow)
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
    
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        guard isActive else {
            completionHandler(nil)
            return
        }

        let panel = NSOpenPanel()

        panel.title = "Choose Files to Upload"
        panel.message = """
        Selected items will be made available to \
        \(frame.request.url?.host ?? "this website").
        """

        panel.canChooseFiles = true

        panel.canChooseDirectories = false

        panel.allowsMultipleSelection = parameters.allowsMultipleSelection

        guard panel.runModal() == .OK else {
            completionHandler(nil)
            return
        }

        completionHandler(panel.urls)
    }
    
    
}
