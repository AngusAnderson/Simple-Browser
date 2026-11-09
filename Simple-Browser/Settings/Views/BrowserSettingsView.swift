import SwiftUI
import WebKit

@MainActor
struct BrowserSettingsView: View {
    let controller: BrowserController

    @State private var websiteDataSelection: WebsiteDataSelection?

    private struct WebsiteDataSelection: Identifiable {
        let id = UUID()
        let store: WKWebsiteDataStore
        let isPrivate: Bool
    }

    private var privateSession: BrowserSession? {
        controller.tabs.first {
            $0.session.isPrivate
        }?.session
    }

    var body: some View {
        TabView {
            generalPane
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            privacyPane
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }

            websitesPane
                .tabItem {
                    Label("Websites", systemImage: "globe")
                }

            filteringPane
                .tabItem {
                    Label(
                        "Filtering",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
        }
        .padding()
        .frame(width: 660, height: 440)
        .sheet(item: $websiteDataSelection) { selection in
            WebsiteDataView(
                controller: controller,
                store: selection.store,
                isPrivate: selection.isPrivate
            )
        }
    }

    private var generalPane: some View {
        Form {
            Picker(
                "Address-bar search",
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

            Toggle(
                "Restore normal tabs on launch",
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

            Text("""
            Restoration saves normal page URLs locally and requests \
            those pages again when the app starts. Private tabs are \
            never restored.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .disabled(controller.isClearingData)
    }

    private var privacyPane: some View {
        Form {
            Toggle(
                "Record normal browsing history",
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

            Text("""
            Private visits are not saved to the visit history. \
            Bookmarks and normal-tab restoration are separate features.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Clear Saved History…") {
                controller.clearHistory()
            }
            .disabled(!controller.library.canWrite)

            Divider()

            Button("Clear Normal Website Data…") {
                controller.requestWebsiteDataReset(
                    isPrivate: false
                )
            }

            Button("End Private Session…") {
                controller.endPrivateSession()
            }

            Text("""
            Website-data resets close tabs and cancel downloads \
            for that mode. Saved files and bookmarks are not deleted.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .disabled(controller.isClearingData)
    }

    private var websitesPane: some View {
        Form {
            Button("Manage Normal Website Data…") {
                websiteDataSelection = WebsiteDataSelection(
                    store: .default(),
                    isPrivate: false
                )
            }

            Button("Manage Active Private Website Data…") {
                guard let session = privateSession else {
                    return
                }

                websiteDataSelection = WebsiteDataSelection(
                    store: session.webView.configuration.websiteDataStore,
                    isPrivate: true
                )
            }
            .disabled(privateSession == nil)

            Divider()

            Text("Camera and microphone")
                .font(.headline)

            Text("""
            Websites request access through the browser's permission \
            prompt. This version does not save Always Allow grants.

            macOS application permissions are controlled separately \
            in System Settings.
            """)
            .foregroundStyle(.secondary)

            Text("""
            Ending the private session also handles private contexts \
            retained by active downloads, even if no private tab is visible.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .disabled(controller.isClearingData)
    }

    private var filteringPane: some View {
        Form {
            Toggle(
                "Enable limited third-party filtering",
                isOn: Binding(
                    get: {
                        controller.contentBlocker.isEnabled
                    },
                    set: {
                        controller.setContentBlockingEnabled($0)
                    }
                )
            )
            .disabled(controller.isClearingData)

            if let error = controller.contentBlocker.errorMessage {
                Text("Rules unavailable: \(error)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if controller.contentBlocker.isReady {
                Text("Bundled rules prepared.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Preparing bundled rules…")
                    .foregroundStyle(.secondary)
            }

            Text("""
            This is a limited bundled rule list, not comprehensive \
            tracking protection. Reload open pages after changing it.

            No blocked-request counter is available.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
