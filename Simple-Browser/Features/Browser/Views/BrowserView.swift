import SwiftUI
import WebKit

struct BrowserView: View {
    
    @State private var preferences = PreferenceStore()
    @State private var browser: BrowserViewModel?

    var body: some View {
        Group {
            if let browser {
                browserContent(browser)
            } else {
                ProgressView("Preparing browser…")
            }
        }
        .task {
            if browser == nil {
                browser = BrowserViewModel(preferences: preferences)
            }
        }
    }

    @ViewBuilder private func browserContent(_ browser: BrowserViewModel) -> some View {
        VStack(spacing: 0) {
            addressBar(browser)

            if let error = browser.lastError {
                errorBanner(error)
            }

            browser.webViewContainer
                .id(browser.isPrivate)
                .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(browser.currentURL?.host ?? "Aegis")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    browser.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browser.canGoBack)
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    browser.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!browser.canGoForward)
                .keyboardShortcut("]", modifiers: .command)

                Button {
                    browser.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                if browser.isLoading {
                    Button {
                        browser.stopLoading()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut(".", modifiers: .command)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { browser.isPrivate },
                    set: { browser.isPrivate = $0 }
                )) {
                    Label(
                        "Private Browsing",
                        systemImage: browser.isPrivate
                            ? "eye.slash.fill"
                            : "eye"
                    )
                }
                .toggleStyle(.switch)

                Menu {
                    Picker("Search engine", selection: Binding(
                        get: { preferences.searchEngine },
                        set: { preferences.searchEngine = $0 }
                    )) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }

                    Divider()

                    Button("Clear Website Data") {
                        browser.clearWebsiteData()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func addressBar(_ browser: BrowserViewModel) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: browser.isSecure
                    ? "lock.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(
                browser.isSecure ? .green : .orange
            )
            .help(
                browser.isSecure
                    ? "Secure connection"
                    : "Insecure connection"
            )

            TextField(
                "Search or enter website address",
                text: Binding(
                    get: { browser.addressText },
                    set: { browser.addressText = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .submitLabel(.go)
            .onSubmit {
                browser.loadAddress()
            }

            if browser.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red)
    }
}
