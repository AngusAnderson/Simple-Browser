import Foundation
import Observation

@Observable final class PreferenceStore {
    private let defaults: UserDefaults

    private enum Key {
        static let searchEngine = "searchEngine"
        static let homepage = "homepage"
        static let privateBrowsingEnabled = "privateBrowsingEnabled"
    }

    var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: Key.searchEngine)
        }
    }

    var homepage: URL {
        didSet {
            defaults.set(homepage.absoluteString, forKey: Key.homepage)
        }
    }

    var privateBrowsingEnabled: Bool {
        didSet {
            defaults.set(
                privateBrowsingEnabled,
                forKey: Key.privateBrowsingEnabled
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let engineRaw = defaults.string(forKey: Key.searchEngine) ?? ""
        self.searchEngine = SearchEngine(rawValue: engineRaw) ?? .duckduckgo

        guard let defaultHomepage = URL(string: "https://duckduckgo.com") else {
            preconditionFailure("The built-in homepage URL is invalid.")
        }

        let savedHomepage = defaults.string(forKey: Key.homepage)

        if let savedHomepage,
           let url = URL(string: savedHomepage),
           url.scheme?.lowercased() == "https",
           url.host != nil {
            self.homepage = url
        } else {
            self.homepage = defaultHomepage
        }

        self.privateBrowsingEnabled = defaults.object(
            forKey: Key.privateBrowsingEnabled
        ) as? Bool ?? true
    }
}
