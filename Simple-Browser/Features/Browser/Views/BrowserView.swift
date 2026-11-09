import SwiftUI

@MainActor struct BrowserView: View {
    @State private var controller = BrowserController()
    @State private var addressText = ""
    @State private var showingLibrary = false

    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(controller: controller)

            if let session = controller.session {
                addressBar(session)

                if session.isLoading {
                    ProgressView(value: session.progress)
                        .progressViewStyle(.linear)
                }

                if let error = session.errorMessage {
                    messageBar(error, isError: true)
                }

                if let error = controller.library.errorMessage {
                    Text(error)
                        .font(.callout)
                        .padding(10)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(Color.orange.opacity(0.15))
                }

                if let status = controller.statusMessage {
                    messageBar(status, isError: false)
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
        .frame(minWidth: 950, minHeight: 650)
        .navigationTitle(controller.session?.title ?? "Simple Browser")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    controller.session?.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!(controller.session?.canGoBack ?? false))
                .keyboardShortcut("[", modifiers: .command)
                .help("Back")

                Button {
                    controller.session?.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!(controller.session?.canGoForward ?? false))
                .keyboardShortcut("]", modifiers: .command)
                .help("Forward")

                Button {
                    controller.session?.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(controller.session == nil)
                .keyboardShortcut("r", modifiers: .command)
                .help("Reload")

                Button {
                    controller.session?.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(!(controller.session?.isLoading ?? false))
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop loading")
            }

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
                    Label("New Private Tab", systemImage: "eye.slash")
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
                    controller.session?.committedURL == nil
                        || !controller.library.canWrite
                )

                Button {
                    showingLibrary = true
                } label: {
                    Label("Library", systemImage: "books.vertical")
                }
                .disabled(controller.isClearingData)

                settingsMenu
            }
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryView(controller: controller)
        }
        .background {
            Button("Focus Address Bar") {
                addressFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)
            .hidden()
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
        .onChange(of: addressFocused) { _, focused in
            if !focused {
                syncAddress()
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
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

            Divider()

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

            Divider()

            Button("Close Current Tab") {
                if let id = controller.selectedTabID {
                    controller.closeTab(id)
                }
            }
            .disabled(controller.isClearingData)

            Button("Clear This Mode’s Website Data…") {
                controller.clearWebsiteData()
            }
            .disabled(
                controller.session == nil
                    || controller.isClearingData
            )
        } label: {
            Image(systemName: "ellipsis.circle")
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

            Text(session.isPrivate ? "Private" : "Normal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
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
        .background(
            isError
                ? Color.red.opacity(0.12)
                : Color.blue.opacity(0.12)
        )
    }

    private func syncAddress() {
        addressText = controller.session?
            .committedURL?.absoluteString ?? ""
    }
}
