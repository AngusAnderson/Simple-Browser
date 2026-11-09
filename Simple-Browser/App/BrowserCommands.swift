import AppKit
import SwiftUI

@MainActor struct BrowserCommands: Commands {
    let controller: BrowserController

    @FocusedValue(\.browserWindowActions)
    private var windowActions

    private var browserIsActive: Bool {
        windowActions != nil
    }

    private var canUseBrowser: Bool {
        browserIsActive && !controller.isClearingData
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                controller.newTab(isPrivate: false)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!canUseBrowser)

            Button("New Private Tab") {
                controller.newTab(isPrivate: true)
            }
            .keyboardShortcut(
                "p",
                modifiers: [.command, .shift]
            )
            .disabled(!canUseBrowser)
        }

        CommandGroup(replacing: .saveItem) {
            Button(
                browserIsActive
                    ? "Close Tab"
                    : "Close Window"
            ) {
                closeTabOrWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(
                browserIsActive && controller.isClearingData
            )

            Button("Close Window") {
                closeCurrentWindow()
            }
            .keyboardShortcut(
                "w",
                modifiers: [.command, .shift]
            )
            .disabled(
                browserIsActive && controller.isClearingData
            )
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Focus Address Bar") {
                windowActions?.focusAddress()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!canUseBrowser)

            Button("Reload Page") {
                controller.session?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(
                !canUseBrowser || controller.session == nil
            )

            Button("Stop Loading") {
                controller.session?.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(
                !canUseBrowser
                    || !(controller.session?.isLoading ?? false)
            )

            Divider()

            Button("Show Downloads") {
                windowActions?.showDownloads()
            }
            .disabled(!canUseBrowser)
        }

        CommandMenu("History") {
            Button("Back") {
                controller.session?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(
                !canUseBrowser
                    || !(controller.session?.canGoBack ?? false)
            )

            Button("Forward") {
                controller.session?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(
                !canUseBrowser
                    || !(controller.session?.canGoForward ?? false)
            )

            Divider()

            Button("Show Browser Library") {
                windowActions?.showLibrary()
            }
            .disabled(!canUseBrowser)

            Button("Clear Saved History…") {
                controller.clearHistory()
            }
            .disabled(
                !canUseBrowser || !controller.library.canWrite
            )
        }

        CommandMenu("Bookmarks") {
            Button("Bookmark This Page") {
                controller.bookmarkCurrentPage()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(
                !canUseBrowser
                    || !controller.library.canWrite
                    || controller.session?.committedURL == nil
            )

            Button("Show Bookmarks") {
                windowActions?.showLibrary()
            }
            .disabled(!canUseBrowser)
        }
    }

    private func closeTabOrWindow() {
        guard browserIsActive else {
            NSApp.keyWindow?.performClose(nil)
            return
        }

        guard !controller.isClearingData else {
            return
        }

        if controller.tabs.count > 1 {
            if let id = controller.selectedTabID {
                controller.closeTab(id)
            }
        } else {
            closeCurrentWindow()
        }
    }

    private func closeCurrentWindow() {
        guard browserIsActive else {
            NSApp.keyWindow?.performClose(nil)
            return
        }

        guard !controller.isClearingData else {
            return
        }

        let hasActiveDownloads = controller.downloads.items.contains {
            $0.state.isActive
        }

        if hasActiveDownloads {
            let confirmed = NativeDialogs.confirm(
                title: "Close the browser window?",
                message: """
                Downloads are still active.
                Closing the main browser window may end the app \
                and interrupt those transfers.
                """,
                accept: "Close Window"
            )

            guard confirmed else {
                return
            }
        }

        NSApp.keyWindow?.performClose(nil)
    }
}
