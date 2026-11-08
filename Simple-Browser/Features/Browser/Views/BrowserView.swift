import SwiftUI

@MainActor
struct BrowserView: View {
    @State private var controller = BrowserController()
    @State private var addressText = ""

    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let session = controller.session {
                addressBar(session)

                if session.isLoading {
                    ProgressView(value: session.progress)
                        .progressViewStyle(.linear)
                }

                if let error = session.errorMessage {
                    banner(error, isError: true)
                }

                if let status = controller.statusMessage {
                    banner(status, isError: false)
                }

                WebViewContainer(webView: session.webView)
                    .id(session.id)
            } else {
                ProgressView(
                    controller.isClearingData
                        ? "Clearing website data…"
                        : "Preparing browser…"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(controller.session?.title ?? "Simple Browser")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    controller.session?.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .disabled(!(controller.session?.canGoBack ?? false))
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    controller.session?.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")
                .disabled(!(controller.session?.canGoForward ?? false))
                .keyboardShortcut("]", modifiers: .command)

                Button {
                    controller.session?.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
                .disabled(controller.session == nil)
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    controller.session?.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Stop loading")
                .disabled(!(controller.session?.isLoading ?? false))
                .keyboardShortcut(".", modifiers: .command)
            }

            ToolbarItem {
                Button {
                    controller.switchMode()
                } label: {
                    Label(
                        controller.session?.isPrivate == true
                            ? "Private"
                            : "Normal",
                        systemImage: controller.session?.isPrivate == true
                            ? "eye.slash"
                            : "eye"
                    )
                }
                .help("Switch browsing mode; closes the current page")
                .disabled(controller.session == nil)
            }

            ToolbarItem {
                Menu {
                    Picker(
                        "Address Bar Search Engine",
                        selection: Binding(
                            get: { controller.preferences.searchEngine },
                            set: { controller.preferences.searchEngine = $0 }
                        )
                    ) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.displayName)
                                .tag(engine)
                        }
                    }

                    Divider()

                    Button("Clear This Mode’s Website Data…") {
                        controller.clearWebsiteData()
                    }
                    .disabled(controller.session == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Browser settings")
            }
        }
        .background {
            Button("Focus Address Bar") {
                addressFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)
            .hidden()
        }
        .onChange(
            of: controller.session?.committedURL,
            initial: true
        ) { _, url in
            guard !addressFocused else { return }
            addressText = url?.absoluteString ?? ""
        }
        .onChange(of: addressFocused) { _, focused in
            if !focused {
                addressText = controller.session?
                    .committedURL?.absoluteString ?? ""
            }
        }
    }

    private func addressBar(_ session: BrowserSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: session.connection.symbol)
                .help(session.connection.label)
                .accessibilityLabel(session.connection.label)

            TextField(
                "Search or enter a website address",
                text: $addressText
            )
            .textFieldStyle(.roundedBorder)
            .focused($addressFocused)
            .onSubmit {
                controller.navigate(addressText)
                addressFocused = false
            }

            if session.isPrivate {
                Text("Private")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private func banner(_ text: String, isError: Bool) -> some View {
        HStack {
            Text(text)
                .font(.callout)

            Spacer()

            Button {
                if isError {
                    controller.session?.errorMessage = nil
                } else {
                    controller.statusMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(10)
        .background(
            isError
                ? Color.red.opacity(0.12)
                : Color.blue.opacity(0.12)
        )
    }
}
