import Foundation
import Observation
import WebKit

@MainActor @Observable final class BrowserController {
    let preferences: PreferenceStore

    private(set) var session: BrowserSession?
    private(set) var isClearingData = false

    var statusMessage: String?

    init() {
        preferences = PreferenceStore()
        startSession(isPrivate: preferences.privateBrowsingEnabled)
    }

    func navigate(_ input: String) {
        guard let session else { return }

        guard let url = AddressResolver.resolve(
            input,
            engine: preferences.searchEngine
        ) else {
            session.errorMessage = "Enter a valid website address or search."
            return
        }

        session.load(url)
    }

    func switchMode() {
        guard let current = session, !isClearingData else {
            return
        }

        let nextPrivate = !current.isPrivate

        let confirmed = NativeDialogs.confirm(
            title: nextPrivate
                ? "Start private browsing?"
                : "Start normal browsing?",
            message: """
            This closes the current page and opens a fresh session.
            Normal browsing website data is not deleted by switching modes.
            """,
            accept: "Switch Mode"
        )

        guard confirmed else { return }

        current.shutdown()
        session = nil

        preferences.privateBrowsingEnabled = nextPrivate
        statusMessage = nil
        startSession(isPrivate: nextPrivate)
    }

    func clearWebsiteData() {
        guard let current = session, !isClearingData else {
            return
        }

        let confirmed = NativeDialogs.confirm(
            title: "Clear this mode’s website data?",
            message: """
            The current page will close.

            Cookies, caches, and website storage for this browsing mode \
            will be removed. Normal-mode deletion may sign you out of websites.

            App preferences are kept.
            """,
            accept: "Clear Website Data"
        )

        guard confirmed else { return }

        let mode = current.isPrivate
        let store = current.webView.configuration.websiteDataStore

        current.shutdown()
        session = nil
        isClearingData = true
        statusMessage = nil

        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    self.isClearingData = false
                    self.statusMessage = """
                    Website data cleared. A fresh session has opened.
                    """
                    self.startSession(isPrivate: mode)
                }
            }
        )
    }

    private func startSession(isPrivate: Bool) {
        let freshSession = BrowserSession(isPrivate: isPrivate)
        session = freshSession
        freshSession.load(preferences.homepage)
    }
}
