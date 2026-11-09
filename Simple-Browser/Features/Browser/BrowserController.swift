import Foundation
import Observation
import WebKit

@MainActor @Observable final class BrowserController {
    let preferences: PreferencesStore
    let library: LibraryStore
    
    let downloads = DownloadManager()

    private(set) var tabs: [BrowserTab] = []
    private(set) var selectedTabID: UUID?
    private(set) var isClearingData = false

    var statusMessage: String?

    @ObservationIgnored private var privateDataStore: WKWebsiteDataStore?
    
    var session: BrowserSession? {
        tabs.first {
            $0.id == selectedTabID
        }?.session
    }

    init() {
        preferences = PreferencesStore()
        library = LibraryStore()

        let restoreURLs = preferences.restoreNormalTabs
            ? library.savedTabs.map(\.url)
            : []

        if !preferences.historyEnabled {
            library.clearHistory()
        }

        if !preferences.restoreNormalTabs {
            library.setSavedTabs([])
        }

        if restoreURLs.isEmpty {
            newTab(isPrivate: preferences.privateBrowsingEnabled)
        } else {
            for url in restoreURLs {
                newTab(isPrivate: false, url: url)
            }

            selectedTabID = tabs.first?.id
        }

        library.save()
    }

    func newTab(isPrivate: Bool, url: URL? = nil) {
        guard !isClearingData else { return }

        let dataStore: WKWebsiteDataStore

        if isPrivate {
            if privateDataStore == nil {
                privateDataStore = .nonPersistent()
            }

            guard let store = privateDataStore else { return }
            dataStore = store
        } else {
            dataStore = .default()
        }

        let newSession = BrowserSession(
            isPrivate: isPrivate,
            dataStore: dataStore
        )

        configureSession(newSession)

        let tab = BrowserTab(session: newSession)
        tabs.append(tab)
        selectedTabID = tab.id

        preferences.privateBrowsingEnabled = isPrivate

        newSession.load(url ?? preferences.homepage)
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closeTab(_ id: UUID) {
        guard !isClearingData,
              let index = tabs.firstIndex(where: {
                  $0.id == id
              }) else {
            return
        }

        let wasSelected = selectedTabID == id

        tabs[index].session.shutdown()
        tabs.remove(at: index)

        if wasSelected {
            selectedTabID = tabs.isEmpty
                ? nil
                : tabs[min(index, tabs.count - 1)].id
        }

        discardPrivateStoreIfUnused()
        persist()

        if tabs.isEmpty {
            newTab(isPrivate: preferences.privateBrowsingEnabled)
        }
    }

    func navigate(_ input: String) {
        guard let session else { return }

        guard let url = AddressResolver.resolve(
            input,
            engine: preferences.searchEngine
        ) else {
            session.errorMessage = "Enter a valid address or search."
            return
        }

        session.load(url)
    }

    func open(_ url: URL) {
        guard LibraryStore.isWebURL(url) else { return }
        session?.load(url)
    }

    func bookmarkCurrentPage() {
        guard library.canWrite,
              let session,
              let url = session.committedURL,
              LibraryStore.isWebURL(url) else {
            return
        }

        if session.isPrivate {
            let confirmed = NativeDialogs.confirm(
                title: "Save a private page as a bookmark?",
                message: """
                This page’s title and URL will be stored on this device \
                after the private session ends.
                """,
                accept: "Save Bookmark"
            )

            guard confirmed else { return }
        }

        library.addBookmark(title: session.title, url: url)
        persist()
        statusMessage = "Bookmark added, or already present. Loacl saving runs in the background."
    }

    func removeBookmark(_ id: UUID) {
        library.removeBookmark(id: id)
        persist()
    }

    func removeHistoryEntry(_ id: UUID) {
        library.removeHistoryEntry(id: id)
        persist()
    }

    func clearHistory() {
        guard library.canWrite else { return }

        let confirmed = NativeDialogs.confirm(
            title: "Clear saved browsing history?",
            message: """
            This removes the app’s saved visit list.
            It does not clear cookies, bookmarks, saved tab URLs, \
            or the live tabs’ Back/Forward lists.
            """,
            accept: "Clear History"
        )

        guard confirmed else { return }

        library.clearHistory()
        persist()
        statusMessage = "Saved browsing history cleared."
    }

    func setHistoryEnabled(_ enabled: Bool) {
        guard library.canWrite else { return }

        if !enabled {
            let confirmed = NativeDialogs.confirm(
                title: "Disable and clear history?",
                message: """
                Existing saved history will be deleted.
                Private visits are never recorded.
                """,
                accept: "Disable and Clear"
            )

            guard confirmed else { return }

            library.clearHistory()
        }

        preferences.historyEnabled = enabled
        persist()
    }

    func setRestorationEnabled(_ enabled: Bool) {
        guard library.canWrite else { return }

        if enabled {
            let confirmed = NativeDialogs.confirm(
                title: "Restore normal tabs on launch?",
                message: """
                Normal tabs’ completed page URLs will be saved locally.
                Launching the app will automatically request those pages again.

                Private tabs are never saved.
                """,
                accept: "Enable Restoration"
            )

            guard confirmed else { return }
        }

        preferences.restoreNormalTabs = enabled
        persist()
    }

    func clearWebsiteData() {
        guard let current = session, !isClearingData else {
            return
        }

        let mode = current.isPrivate

        let confirmed = NativeDialogs.confirm(
            title: "Clear this mode’s website data?",
            message: """
            All \(mode ? "private" : "normal") tabs will close.

            Cookies, caches, and website storage for this mode will be \
            cleared. Saved history and bookmarks are separate.
            """,
            accept: "Close Tabs and Clear"
        )

        guard confirmed else { return }

        let store = current.webView.configuration.websiteDataStore

        isClearingData = true
        statusMessage = nil

        for tab in tabs where tab.session.isPrivate == mode {
            tab.session.shutdown()
        }

        tabs.removeAll { $0.session.isPrivate == mode }

        if !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = tabs.first?.id
        }

        discardPrivateStoreIfUnused()
        persist()

        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    self.isClearingData = false
                    self.statusMessage = "Website-data clearing completed."

                    if self.tabs.isEmpty {
                        self.newTab(
                            isPrivate: self.preferences.privateBrowsingEnabled
                        )
                    }
                }
            }
        )
    }

    private func pageFinished(_ finishedSession: BrowserSession) {
        guard tabs.contains(where: {
            $0.id == finishedSession.id
        }) else {
            return
        }

        if preferences.historyEnabled,
           !finishedSession.isPrivate,
           let url = finishedSession.committedURL {
            library.recordVisit(
                title: finishedSession.title,
                url: url
            )
        }

        persist()
    }

    private func persist() {
        if preferences.restoreNormalTabs {
            let saved = tabs.compactMap { tab -> SavedTab? in
                guard !tab.session.isPrivate,
                      let url = tab.session.committedURL,
                      LibraryStore.isWebURL(url) else {
                    return nil
                }

                return SavedTab(url: url)
            }

            library.setSavedTabs(saved)
        } else {
            library.setSavedTabs([])
        }

        library.save()
    }

    private func discardPrivateStoreIfUnused() {
        if !tabs.contains(where: { $0.session.isPrivate }) {
            privateDataStore = nil
        }
    }
    
    private func configureSession(_ session: BrowserSession) {
        session.onPageFinished = { [weak self] finished in
            self?.pageFinished(finished)
        }

        session.onDownload = { [weak self, weak session] download in
            guard let self, let session else {
                download.cancel(nil)
                return
            }

            self.downloads.accept(
                download,
                sourceView: session.webView,
                isPrivate: session.isPrivate
            )

            self.statusMessage = """
            Download started. Open Downloads to view its status.
            """
        }

        session.onOpenRequest = {
            [weak self, weak session] request, select in

            guard let self, let session else {
                return
            }

            self.openRequestInTab(
                request,
                from: session,
                select: select
            )
        }

        session.onCreateWebView = {
            [weak self, weak session] configuration, select in

            guard let self, let session else {
                return nil
            }

            return self.adoptWebView(
                configuration: configuration,
                from: session,
                select: select
            )
        }

        session.onCloseRequested = { [weak self, weak session] in
            guard let self, let session else {
                return
            }

            self.closeTab(session.id)
        }
    }
    
    private func openRequestInTab(
        _ request: URLRequest,
        from source: BrowserSession,
        select: Bool
    ) {
        guard !isClearingData else {
            return
        }

        let session = BrowserSession(
            isPrivate: source.isPrivate,
            dataStore: source.webView.configuration.websiteDataStore
        )

        configureSession(session)

        let tab = BrowserTab(session: session)
        tabs.append(tab)

        if select {
            selectedTabID = tab.id
        }

        session.webView.load(request)
    }
    
    private func adoptWebView(
        configuration: WKWebViewConfiguration,
        from source: BrowserSession,
        select: Bool
    ) -> WKWebView? {
        guard !isClearingData else {
            return nil
        }

        guard !source.isPrivate
            || !configuration.websiteDataStore.isPersistent else {
            statusMessage = """
            A new browsing context was blocked because its storage \
            did not match private browsing.
            """
            return nil
        }

        let session = BrowserSession(
            isPrivate: source.isPrivate,
            configuration: configuration
        )

        configureSession(session)

        let tab = BrowserTab(session: session)
        tabs.append(tab)

        if select {
            selectedTabID = tab.id
        }

        return session.webView
    }
}
