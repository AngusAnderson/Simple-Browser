import Foundation
import Observation
import WebKit

@MainActor @Observable final class BrowserController {
    let preferences: PreferencesStore
    let library: LibraryStore
    
    let downloads = DownloadManager()
    
    let contentBlocker = ContentBlocker()

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

        loadWhenRulesAreReady(
            URLRequest(url: url ?? preferences.homepage),
            in: newSession
        )
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
        guard !isClearingData,
              let session else {
            return
        }

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
        guard !isClearingData, LibraryStore.isWebURL(url) else { return }
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
    
    func setContentBlockingEnabled(_ enabled: Bool) {
        guard !isClearingData else {
            return
        }

        contentBlocker.isEnabled = enabled

        contentBlocker.prepare { [weak self] in
            guard let self else {
                return
            }

            for tab in self.tabs {
                self.contentBlocker.apply(
                    to: tab.session.webView.configuration
                )
            }

            if let error = self.contentBlocker.errorMessage {
                self.statusMessage = """
                Content blocking could not be prepared: \(error)
                """
            } else {
                self.statusMessage = """
                Limited content blocking \(enabled ? "enabled" : "disabled").
                Reload open pages to test the changed setting.
                """
            }
        }
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
        guard let current = session else {
            return
        }

        requestWebsiteDataReset(isPrivate: current.isPrivate)
    }

    func endPrivateSession() {
        requestWebsiteDataReset(isPrivate: true)
    }

    func requestWebsiteDataReset(
        isPrivate: Bool,
        records: [WKWebsiteDataRecord]? = nil,
        selectedStore: WKWebsiteDataStore? = nil
    ) {
        guard !isClearingData else {
            return
        }

        guard records == nil || selectedStore != nil else {
            return
        }

        let selectedOnly = records != nil

        let confirmed = NativeDialogs.confirm(
            title: selectedOnly
                ? "Delete selected website data?"
                : (
                    isPrivate
                        ? "End private session and clear its data?"
                        : "Clear normal website data?"
                ),
            message: """
            All \(isPrivate ? "private" : "normal") tabs will close.
            Downloads for that mode will be cancelled first.

            \(selectedOnly
                ? "Only the selected website records will be deleted."
                : "Website data for this mode will be deleted.")

            Saved history and bookmarks will not be deleted.
            Downloaded files will not be deleted.

            Closed normal tabs will also be removed from the \
            tab-restoration snapshot.
            """,
            accept: "Continue"
        )

        guard confirmed else {
            return
        }

        isClearingData = true
        downloads.blockNewDownloads(isPrivate: isPrivate)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.performWebsiteDataReset(
                isPrivate: isPrivate,
                records: records,
                selectedStore: selectedStore
            )
        }
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
    
    private func performWebsiteDataReset(
        isPrivate: Bool,
        records: [WKWebsiteDataRecord]?,
        selectedStore: WKWebsiteDataStore?
    ) async {
        statusMessage = nil

        var stores = tabs
            .filter { $0.session.isPrivate == isPrivate }
            .map { $0.session.webView.configuration.websiteDataStore }

        stores += downloads.websiteDataStores(isPrivate: isPrivate)

        if isPrivate {
            if let privateDataStore {
                stores.append(privateDataStore)
            }
        } else {
            stores.append(.default())
        }

        if let selectedStore {
            stores.append(selectedStore)
        }

        for tab in tabs where tab.session.isPrivate == isPrivate {
            tab.session.shutdown()
        }

        tabs.removeAll {
            $0.session.isPrivate == isPrivate
        }

        if !tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = tabs.first?.id
        }

        await downloads.cancelAndWait(isPrivate: isPrivate)

        if let records, let selectedStore {
            await WebsiteDataManager.remove(
                records: records,
                from: selectedStore
            )
        } else {
            var visited = Set<ObjectIdentifier>()

            for store in stores {
                let identifier = ObjectIdentifier(store)

                guard visited.insert(identifier).inserted else {
                    continue
                }

                await WebsiteDataManager.remove(
                    records: nil,
                    from: store
                )
            }
        }

        if isPrivate {
            privateDataStore = nil
        }

        persist()

        downloads.unblockNewDownloads(isPrivate: isPrivate)
        isClearingData = false

        statusMessage = records == nil
            ? "Website-data reset completed."
            : "Selected website-data deletion completed."

        if tabs.isEmpty {
            // Do not immediately revisit the homepage and recreate its data.
            newTab(
                isPrivate: isPrivate,
                url: URL(string: "about:blank")!
            )
        }
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
    
    private func loadWhenRulesAreReady(
        _ request: URLRequest,
        in session: BrowserSession
    ) {
        contentBlocker.prepare { [weak self, weak session] in
            guard let self,
                  let session,
                  !self.isClearingData,
                  self.tabs.contains(where: {
                      $0.id == session.id
                  }) else {
                return
            }

            self.contentBlocker.apply(
                to: session.webView.configuration
            )

            if let error = self.contentBlocker.errorMessage {
                self.statusMessage = """
                Content blocking is unavailable: \(error)
                """
            }

            session.webView.load(request)
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

        loadWhenRulesAreReady(
            request,
            in: session
        )
    }
    
    private func adoptWebView(
        configuration: WKWebViewConfiguration,
        from source: BrowserSession,
        select: Bool
    ) -> WKWebView? {
        guard !isClearingData else {
            return nil
        }

        guard contentBlocker.isReady else {
            statusMessage = "Please retry after browser rules finish preparing."
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

        contentBlocker.apply(to: configuration)

        let childSession = BrowserSession(
            isPrivate: source.isPrivate,
            configuration: configuration
        )

        configureSession(childSession)

        let sourceID = source.id

        DispatchQueue.main.async { [weak self, childSession] in
            guard let self else {
                childSession.shutdown()
                return
            }

            guard !self.isClearingData,
                  self.tabs.contains(where: {
                      $0.id == sourceID
                  }) else {
                childSession.shutdown()
                return
            }

            let tab = BrowserTab(session: childSession)
            self.tabs.append(tab)

            if select {
                self.selectedTabID = tab.id
            }
        }

        return childSession.webView
    }
}
