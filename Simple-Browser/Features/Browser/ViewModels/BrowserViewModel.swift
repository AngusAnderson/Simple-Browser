import SwiftUI
import WebKit

@Observable final class BrowserViewModel: NSObject, WKNavigationDelegate {
    enum NavigationError: LocalizedError {
        case invalidAddress
        
        var errorDescription: String? {
            switch self {
                case .invalidAddress: "That address could not be opened"
            }
        }
    }
    
    private(set) var currentURL: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isSecure = true
    private(set) var lastError: String?
    
    var addressText = ""
    var isPrivate: Bool {
        didSet {
            guard oldValue != isPrivate else {
                return
            }

            preferences.privateBrowsingEnabled = isPrivate

            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil

            currentURL = nil
            addressText = ""
            isLoading = false
            canGoBack = false
            canGoForward = false
            isSecure = false
            lastError = nil
        }
    }
    
    let preferences: PreferenceStore
    
    private var webView: WKWebView?
    
    init(preferences: PreferenceStore) {
        self.preferences = preferences
        self.isPrivate = preferences.privateBrowsingEnabled
        
        super.init()
        
        addressText = preferences.homepage.absoluteString
    }
    
    var webViewContainer: WebViewContainer {
        WebViewContainer(isPrivate: isPrivate) { [weak self] createdWebView in
            self?.attach(createdWebView)
        }
    }
    
    func loadAddress() {
        lastError = nil
        
        guard let url = URLValidator.url(
            from: addressText,
            searchEngine: preferences.searchEngine
        ) else {
            lastError = NavigationError.invalidAddress.localizedDescription
            return
        }
        
        load(url: url)
    }
    
    func load(url: URL) {
        guard let webView else {
            lastError = "The browser is still preparing. Please try again."
            return
        }

        lastError = nil
        addressText = url.absoluteString

        webView.load(URLRequest(url: url))
    }
    
    func loadHomepage() {
        load(url: preferences.homepage)
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func stopLoading() {
        webView?.stopLoading()
    }
    
    func clearWebsiteData() {
        guard let webView else {
            return
        }

        let dataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        dataStore.removeData(
            ofTypes: dataTypes,
            modifiedSince: Date.distantPast,
            completionHandler: {}
        )
    }
    
    private func attach(_ createdWebView: WKWebView) {
        webView = createdWebView
        createdWebView.navigationDelegate = self

        loadHomepage()
    }
}

extension BrowserViewModel {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastError = nil
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentURL = webView.url
        addressText = webView.url?.absoluteString ?? addressText
        isSecure = URLValidator.isSecure(webView.url)
        refreshNavigationState(webView)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        lastError = error.localizedDescription
        refreshNavigationState(webView)
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        guard url.scheme == "https" || url.scheme == "http" else {
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    private func refreshNavigationState(_ webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}
