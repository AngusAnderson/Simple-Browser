import SwiftUI
import AppKit
import WebKit

@MainActor
struct BrowserView: View {
    @State private var controller = BrowserController()
    @State private var addressText = ""
    @State private var presentedSheet: BrowserSheet?

    @FocusState private var addressFocused: Bool

    // MARK: - Sheet Routing

    private enum BrowserSheet: Identifiable {
        case library
        case downloads

        case websiteData(
            store: WKWebsiteDataStore,
            isPrivate: Bool
        )

        var id: String {
            switch self {
            case .library:
                return "library"

            case .downloads:
                return "downloads"

            case .websiteData:
                return "website-data"
            }
        }
    }

    // MARK: - Main View

    var body: some View {
        browserContent
            .frame(minWidth: 950, minHeight: 650)
            .navigationTitle(
                controller.session?.title ?? "Simple Browser"
            )
            .toolbar {
                navigationToolbar
                actionToolbar
            }
            .sheet(item: $presentedSheet) { sheet in
                sheetContent(sheet)
            }
            .background {
                focusAddressShortcut
            }
            .onChange(
                of: controller.selectedTabID,
                initial: true
            ) { _, _ in
                addressFocused = false
                syncAddress()
            }
            .onChange(
                of: controller.session?.committedURL
            ) { _, _ in
                if !addressFocused {
                    syncAddress()
                }
            }
            .onChange(
                of: addressFocused
            ) { _, focused in
                if !focused {
                    syncAddress()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification
                )
            ) { _ in
                controller.library.finishPendingWrites()
            }
    }

    // MARK: - Browser Content

    private var browserContent: some View {
        VStack(spacing: 0) {
            TabStrip(controller: controller)
                .disabled(controller.isClearingData)

            if controller.isClearingData {
                waitingView("Clearing website data…")
            } else if let session = controller.session {
                sessionContent(session)
            } else {
                waitingView("Preparing browser…")
            }
        }
    }

    @ViewBuilder
    private func sessionContent(
        _ session: BrowserSession
    ) -> some View {
        addressBar(session)
            .disabled(controller.isClearingData)

        PageLoadProgress(session: session)

        if let error = session.errorMessage {
            messageBar(error, isError: true)
        }

        if let error = controller.library.errorMessage {
            libraryErrorBanner(error)
        }

        if let status = controller.statusMessage {
            messageBar(status, isError: false)
        }

        WebViewContainer(webView: session.webView)
            .id(session.id)
    }

    private func waitingView(
        _ message: String
    ) -> some View {
        ProgressView(message)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
    }

    // MARK: - Navigation Toolbar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                controller.session?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(
                controller.isClearingData
                    || !(controller.session?.canGoBack ?? false)
            )
            .keyboardShortcut("[", modifiers: .command)
            .help("Back")

            Button {
                controller.session?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(
                controller.isClearingData
                    || !(controller.session?.canGoForward ?? false)
            )
            .keyboardShortcut("]", modifiers: .command)
            .help("Forward")

            Button {
                controller.session?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(
                controller.isClearingData
                    || controller.session == nil
            )
            .keyboardShortcut("r", modifiers: .command)
            .help("Reload")

            Button {
                controller.session?.stop()
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(
                controller.isClearingData
                    || !(controller.session?.isLoading ?? false)
            )
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop loading")
        }
    }

    // MARK: - Action Toolbar

    @ToolbarContentBuilder
    private var actionToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                controller.newTab(isPrivate: false)
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(controller.isClearingData)

            Button {
                controller.newTab(isPrivate: true)
            } label: {
                Label(
                    "New Private Tab",
                    systemImage: "eye.slash"
                )
            }
            .keyboardShortcut(
                "p",
                modifiers: [.command, .shift]
            )
            .disabled(controller.isClearingData)

            Button {
                controller.bookmarkCurrentPage()
            } label: {
                Image(systemName: "bookmark")
            }
            .help("Bookmark current page")
            .keyboardShortcut("d", modifiers: .command)
            .disabled(
                controller.isClearingData
                    || controller.session?.committedURL == nil
                    || !controller.library.canWrite
            )

            Button {
                presentedSheet = .library
            } label: {
                Label(
                    "Library",
                    systemImage: "books.vertical"
                )
            }
            .disabled(controller.isClearingData)

            Button {
                presentedSheet = .downloads
            } label: {
                Label(
                    "Downloads",
                    systemImage: "arrow.down.circle"
                )
            }
            .help("Show downloads")
            .disabled(controller.isClearingData)
        }

        ToolbarItem {
            settingsMenu
        }
    }

    // MARK: - Settings Menu

    private var settingsMenu: some View {
        Menu {
            searchEnginePicker

            Divider()

            persistenceSettings

            Divider()

            contentBlockingSetting

            Divider()

            privacyActions

            Divider()

            Button("Close Current Tab") {
                guard let id = controller.selectedTabID else {
                    return
                }

                controller.closeTab(id)
            }
            .disabled(
                controller.isClearingData
                    || controller.selectedTabID == nil
            )
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("Browser settings")
        .disabled(controller.isClearingData)
    }

    private var searchEnginePicker: some View {
        Picker(
            "Address Bar Search Engine",
            selection: Binding(
                get: {
                    controller.preferences.searchEngine
                },
                set: {
                    controller.preferences.searchEngine = $0
                }
            )
        ) {
            ForEach(SearchEngine.allCases) { engine in
                Text(engine.displayName)
                    .tag(engine)
            }
        }
    }

    @ViewBuilder
    private var persistenceSettings: some View {
        Toggle(
            "Record Normal Browsing History",
            isOn: Binding(
                get: {
                    controller.preferences.historyEnabled
                },
                set: {
                    controller.setHistoryEnabled($0)
                }
            )
        )
        .disabled(!controller.library.canWrite)

        Toggle(
            "Restore Normal Tabs on Launch",
            isOn: Binding(
                get: {
                    controller.preferences.restoreNormalTabs
                },
                set: {
                    controller.setRestorationEnabled($0)
                }
            )
        )
        .disabled(!controller.library.canWrite)
    }

    private var contentBlockingSetting: some View {
        Toggle(
            "Limited Third-Party Filtering",
            isOn: Binding(
                get: {
                    controller.contentBlocker.isEnabled
                },
                set: {
                    controller.setContentBlockingEnabled($0)
                }
            )
        )
    }

    @ViewBuilder
    private var privacyActions: some View {
        Button("Website Data…") {
            showWebsiteData()
        }
        .disabled(controller.session == nil)

        Button("Clear This Mode’s Website Data…") {
            controller.clearWebsiteData()
        }
        .disabled(controller.session == nil)

        Button("End Private Session…") {
            controller.endPrivateSession()
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(
        _ sheet: BrowserSheet
    ) -> some View {
        switch sheet {
        case .library:
            LibraryView(controller: controller)

        case .downloads:
            DownloadsView(manager: controller.downloads)

        case let .websiteData(store, isPrivate):
            WebsiteDataView(
                controller: controller,
                store: store,
                isPrivate: isPrivate
            )
        }
    }

    private func showWebsiteData() {
        guard !controller.isClearingData,
              let session = controller.session else {
            return
        }

        presentedSheet = .websiteData(
            store: session.webView.configuration.websiteDataStore,
            isPrivate: session.isPrivate
        )
    }

    // MARK: - Address Bar

    private func addressBar(
        _ session: BrowserSession
    ) -> some View {
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
                let submittedText = addressText

                addressFocused = false
                controller.navigate(submittedText)
            }

            Text(session.isPrivate ? "Private" : "Normal")
                .font(.caption)
                .foregroundStyle(.secondary)

            LibrarySaveStatus(store: controller.library)
        }
        .padding(10)
    }

    private var focusAddressShortcut: some View {
        Button("Focus Address Bar") {
            addressFocused = true
        }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(controller.isClearingData)
        .hidden()
    }

    private func syncAddress() {
        addressText = controller.session?
            .committedURL?.absoluteString ?? ""
    }

    // MARK: - Messages

    private func libraryErrorBanner(
        _ text: String
    ) -> some View {
        Text(text)
            .font(.callout)
            .padding(10)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background(Color.orange.opacity(0.15))
    }

    private func messageBar(
        _ text: String,
        isError: Bool
    ) -> some View {
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
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            isError
                ? Color.red.opacity(0.12)
                : Color.blue.opacity(0.12)
        )
    }
}
