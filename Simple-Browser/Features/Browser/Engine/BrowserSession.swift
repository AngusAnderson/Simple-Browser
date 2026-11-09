import AppKit
import Foundation
import Observation
import WebKit

// MARK: - Connection State

enum ConnectionState {
    case noPage
    case loading
    case encrypted
    case notFullyEncrypted
    case failed

    var label: String {
        switch self {
        case .noPage:
            return "No page loaded"

        case .loading:
            return "Loading"

        case .encrypted:
            return "Connection encrypted—not a website safety rating"

        case .notFullyEncrypted:
            return "Connection is not fully encrypted"

        case .failed:
            return "Navigation failed"
        }
    }

    var symbol: String {
        switch self {
        case .noPage:
            return "globe"

        case .loading:
            return "arrow.triangle.2.circlepath"

        case .encrypted:
            return "lock"

        case .notFullyEncrypted:
            return "exclamationmark.triangle"

        case .failed:
            return "exclamationmark.circle"
        }
    }
}

// MARK: - Browser Session

@MainActor @Observable final class BrowserSession: NSObject {
    let id = UUID()
    let isPrivate: Bool

    @ObservationIgnored
    let webView: WKWebView

    @ObservationIgnored
    private var observations: [NSKeyValueObservation] = []

    @ObservationIgnored
    private var isActive = true

    @ObservationIgnored
    private var expectsDownloadPolicyInterruption = false

    // MARK: Controller Callbacks

    @ObservationIgnored
    var onPageFinished: ((BrowserSession) -> Void)?

    @ObservationIgnored
    var onDownload: ((WKDownload) -> Void)?

    @ObservationIgnored
    var onOpenRequest: ((URLRequest, Bool) -> Void)?

    @ObservationIgnored
    var onCreateWebView: (
        (WKWebViewConfiguration, Bool) -> WKWebView?
    )?

    @ObservationIgnored
    var onCloseRequested: (() -> Void)?

    // MARK: Observable State

    private(set) var committedURL: URL?
    private(set) var title = "Browser"
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var connection: ConnectionState = .noPage

    var errorMessage: String?

    // MARK: Initialization

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

        configuration.preferences
            .javaScriptCanOpenWindowsAutomatically = false

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

    // MARK: Navigation Actions

    func load(_ url: URL) {
        guard isActive else {
            return
        }

        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        guard isActive else {
            return
        }

        webView.goBack()
    }

    func goForward() {
        guard isActive else {
            return
        }

        webView.goForward()
    }

    func reload() {
        guard isActive else {
            return
        }

        errorMessage = nil
        webView.reload()
    }

    func stop() {
        guard isActive else {
            return
        }

        webView.stopLoading()
    }

    // MARK: Lifecycle

    func shutdown() {
        guard isActive else {
            return
        }

        isActive = false
        expectsDownloadPolicyInterruption = false

        onPageFinished = nil
        onDownload = nil
        onOpenRequest = nil
        onCreateWebView = nil
        onCloseRequested = nil

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        observations.forEach {
            $0.invalidate()
        }

        observations.removeAll()
    }

    // MARK: State Helpers

    private func refreshState() {
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward

        title = webView.title
            ?? committedURL?.host
            ?? "Browser"

        if !isLoading, errorMessage == nil {
            updateConnection()
        }
    }

    private func updateConnection() {
        guard let url = committedURL else {
            connection = .noPage
            return
        }

        if url.absoluteString == "about:blank" {
            connection = .noPage
        } else if url.scheme?.lowercased() == "https",
                  webView.hasOnlySecureContent {
            connection = .encrypted
        } else {
            connection = .notFullyEncrypted
        }
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError

        let isPolicyInterruption =
            nsError.domain == "WebKitErrorDomain"
            && nsError.code
                == WebKitErrorFrameLoadInterruptedByPolicyChange

        if expectsDownloadPolicyInterruption,
           isPolicyInterruption {
            expectsDownloadPolicyInterruption = false

            isLoading = webView.isLoading
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward

            updateConnection()
            return
        }

        let isCancellation =
            nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorCancelled

        if isCancellation {
            refreshState()
            return
        }

        expectsDownloadPolicyInterruption = false
        errorMessage = error.localizedDescription
        connection = .failed

        refreshState()
    }

    private func handOffDownload(_ download: WKDownload) {
        guard isActive else {
            download.cancel(nil)
            return
        }

        isLoading = false

        guard let onDownload else {
            download.cancel(nil)
            errorMessage = "The download manager is unavailable."
            return
        }

        onDownload(download)
    }

    private func dialogTitle(for frame: WKFrameInfo) -> String {
        let host = frame.request.url?.host ?? "Unknown origin"
        return "Website dialog — \(host)"
    }

    // MARK: Observation

    private func installObservations() {
        observations = [
            webView.observe(
                \.estimatedProgress,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else {
                        return
                    }

                    self.progress = self.webView.estimatedProgress
                }
            },

            webView.observe(
                \.isLoading,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else {
                        return
                    }

                    self.isLoading = self.webView.isLoading

                    if !self.isLoading,
                       self.errorMessage == nil {
                        self.updateConnection()
                    }
                }
            },

            webView.observe(
                \.canGoBack,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else {
                        return
                    }

                    self.canGoBack = self.webView.canGoBack
                }
            },

            webView.observe(
                \.canGoForward,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else {
                        return
                    }

                    self.canGoForward = self.webView.canGoForward
                }
            },

            webView.observe(
                \.title,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else {
                        return
                    }

                    self.title = self.webView.title
                        ?? self.committedURL?.host
                        ?? "Browser"
                }
            },

            webView.observe(
                \.url,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else {
                        return
                    }

                    if !self.webView.isLoading,
                       self.committedURL != nil,
                       self.errorMessage == nil {
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
                          self.errorMessage == nil else {
                        return
                    }

                    self.updateConnection()
                }
            }
        ]
    }
}

// MARK: - Navigation Delegate

extension BrowserSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        expectsDownloadPolicyInterruption = false
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

    func webViewWebContentProcessDidTerminate(
        _ webView: WKWebView
    ) {
        errorMessage = "The webpage process stopped. Reload to try again."
        connection = .failed
        isLoading = false
    }

    // MARK: Navigation Action Policy

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        #if DEBUG
        print(
            "[Navigation]",
            "type:", navigationAction.navigationType.rawValue,
            "sourceIsMain:", navigationAction.sourceFrame.isMainFrame,
            "targetIsNil:", navigationAction.targetFrame == nil
        )
        #endif

        guard isActive,
              let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        switch NavigationPolicy.decision(for: url) {
        case .allow:
            break

        case .confirmHTTP:
            let isTopLevel =
                navigationAction.targetFrame == nil
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

            guard accepted, isActive else {
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

            if accepted, isActive {
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
            expectsDownloadPolicyInterruption = true
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

            guard let onOpenRequest else {
                errorMessage = "Opening a new tab is unavailable."
                return
            }

            onOpenRequest(
                navigationAction.request,
                false
            )

            return
        }

        decisionHandler(.allow)
    }

    // MARK: Navigation Response Policy

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
            expectsDownloadPolicyInterruption = true
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    // MARK: Download Conversion

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
}

// MARK: - UI Delegate

extension BrowserSession: WKUIDelegate {
    // MARK: New Browsing Contexts

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard isActive else {
            return nil
        }

        let isClickedLink =
            navigationAction.navigationType == .linkActivated

        let isCommandClick =
            navigationAction.modifierFlags.contains(.command)

        if isClickedLink, !isCommandClick {
            let request = navigationAction.request

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else {
                    return
                }

                self.errorMessage = nil
                self.webView.load(request)
            }

            return nil
        }

        guard let createChild = onCreateWebView else {
            errorMessage = "Opening a new tab is unavailable."
            return nil
        }

        if !isClickedLink {
            let accepted = NativeDialogs.confirm(
                title: "Allow a new tab?",
                message: """
                \(committedURL?.host ?? "This website") requested \
                another browsing context.

                Allow this only if it matches something you just did, \
                such as signing in.
                """,
                accept: "Open Tab"
            )

            guard accepted, isActive else {
                return nil
            }
        }

        let selectNewTab = !isCommandClick

        return createChild(
            configuration,
            selectNewTab
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard isActive else {
            return
        }

        onCloseRequested?()
    }

    // MARK: JavaScript Dialogs

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard isActive else {
            completionHandler()
            return
        }

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
        guard isActive else {
            completionHandler(false)
            return
        }

        let accepted = NativeDialogs.confirm(
            title: dialogTitle(for: frame),
            message: message,
            accept: "OK"
        )

        completionHandler(isActive && accepted)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard isActive else {
            completionHandler(nil)
            return
        }

        let result = NativeDialogs.prompt(
            title: dialogTitle(for: frame),
            message: prompt,
            defaultText: defaultText
        )

        completionHandler(isActive ? result : nil)
    }

    // MARK: File Uploads

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

        guard panel.runModal() == .OK,
              isActive else {
            completionHandler(nil)
            return
        }

        completionHandler(panel.urls)
    }

    // MARK: Camera and Microphone

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard isActive else {
            decisionHandler(.deny)
            return
        }

        let decision = PermissionCoordinator.requestMedia(
            origin: origin,
            frame: frame,
            type: type,
            topLevelURL: committedURL,
            isPrivate: isPrivate
        )

        decisionHandler(isActive ? decision : .deny)
    }
}
