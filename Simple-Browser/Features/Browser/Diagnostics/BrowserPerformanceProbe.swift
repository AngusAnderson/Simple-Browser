import SwiftUI
import WebKit

@MainActor struct BrowserPerformanceProbe: View {
    
    @State private var webView: WKWebView?
    @State private var address = "https://duckduckgo.com/"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Website address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        loadAddress()
                    }
                
                Button("Open") {
                    loadAddress()
                }
                
                Button("Local scroll test") {
                    loadLocalTest()
                }
            }
            .padding(10)
            
            if let webView {
                ProbeWebView(webView: webView)
            } else {
                ProgressView("Preparing test...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 950, minHeight: 650)
        .task {
            guard webView == nil else { return }
            
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            
            let view = WKWebView(frame: .zero, configuration: configuration)
            
            webView = view
            loadLocalTest()
        }
    }
    
    private func loadAddress() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil else { return }
        
        webView?.load(URLRequest(url: url))
    }
    
    private func loadLocalTest() {
        let sections = (1...250).map { index in
            """
            <section>
                <h2>Section \(index)</h2>
                <p>
                    This is a local scrolling test. It contains no remote
                    resources, images, animations, or JavaScript.
                    Scroll continuously up and down to check whether the
                    basic native web view feels responsive.
                </p>
            </section>
            """
        }.joined()
        
        let html = """
            <!doctype html>
            <html>
            <head>
                <meta name="viewport"
                      content="width=device-width, initial-scale=1">
                <style>
                    :root {
                        color-scheme: light dark;
                    }

                    body {
                        font-family: -apple-system, sans-serif;
                        max-width: 850px;
                        margin: 0 auto;
                        padding: 32px;
                        line-height: 1.65;
                    }

                    section {
                        padding: 20px 0;
                        border-bottom: 1px solid #8885;
                    }
                </style>
            </head>
            <body>
                <h1>Native WebKit scrolling test</h1>
                \(sections)
            </body>
            </html>
            """
        
        webView?.loadHTMLString(html, baseURL: nil)
    }
}

@MainActor private struct ProbeWebView: NSViewRepresentable {
    let webView: WKWebView
    
    func makeNSView(context: Context) -> WKWebView {
        webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Bwah
    }
}
