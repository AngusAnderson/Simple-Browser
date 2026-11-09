import Foundation
import Observation

@MainActor @Observable final class PreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults

    var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: "searchEngine")
        }
    }

    var privateBrowsingEnabled: Bool {
        didSet {
            defaults.set(
                privateBrowsingEnabled,
                forKey: "privateBrowsingEnabled"
            )
        }
    }

    var historyEnabled: Bool {
        didSet {
            defaults.set(historyEnabled, forKey: "historyEnabled")
        }
    }

    var restoreNormalTabs: Bool {
        didSet {
            defaults.set(
                restoreNormalTabs,
                forKey: "restoreNormalTabs"
            )
        }
    }

    let homepage = URL(string: "https://duckduckgo.com/")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        searchEngine = SearchEngine(
            rawValue: defaults.string(forKey: "searchEngine") ?? ""
        ) ?? .duckduckgo

        privateBrowsingEnabled = defaults.object(
            forKey: "privateBrowsingEnabled"
        ) as? Bool ?? true

        historyEnabled = defaults.bool(forKey: "historyEnabled")
        restoreNormalTabs = defaults.bool(forKey: "restoreNormalTabs")
    }
}
