import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class ContentBlocker {
    private(set) var isReady = false
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                isEnabled,
                forKey: "limitedContentBlockingEnabled"
            )
        }
    }

    @ObservationIgnored
    private var compiledList: WKContentRuleList?

    @ObservationIgnored
    private var isPreparing = false

    @ObservationIgnored
    private var waiting: [() -> Void] = []

    private static let identifier = "limited-third-party-rules-v2"

    private static let rules = #"""
    [
        {
            "trigger": {
                "url-filter": "^https?://([a-z0-9-]+\\.)*google-analytics\\.com/",
                "load-type": ["third-party"]
            },
            "action": {
                "type": "block"
            }
        },
        {
            "trigger": {
                "url-filter": "^https?://([a-z0-9-]+\\.)*doubleclick\\.net/",
                "load-type": ["third-party"]
            },
            "action": {
                "type": "block"
            }
        }
    ]
    """#

    init() {
        isEnabled = UserDefaults.standard.bool(
            forKey: "limitedContentBlockingEnabled"
        )
    }

    func prepare(completion: @escaping () -> Void) {
        if isReady {
            completion()
            return
        }

        waiting.append(completion)

        guard !isPreparing else {
            return
        }

        isPreparing = true

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: Self.identifier,
            encodedContentRuleList: Self.rules
        ) { [weak self] list, error in
            guard let self else {
                return
            }

            self.compiledList = list

            if let error {
                let nsError = error as NSError

                let explanation =
                    nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
                    ?? nsError.userInfo["NSDebugDescription"] as? String
                    ?? nsError.localizedDescription

                self.errorMessage = """
                \(nsError.domain) (\(nsError.code)): \(explanation)
                """

                #if DEBUG
                print("Content-rule compilation failed:")
                print(nsError)
                print(nsError.userInfo)
                #endif
            } else if list == nil {
                self.errorMessage = "No compiled rule list was returned."
            } else {
                self.errorMessage = nil
            }

            self.isPreparing = false
            self.isReady = true

            let callbacks = self.waiting
            self.waiting.removeAll()

            callbacks.forEach { $0() }
        }
    }

    func apply(to configuration: WKWebViewConfiguration) {
        guard let compiledList else {
            return
        }

        let controller = configuration.userContentController

        controller.remove(compiledList)

        if isEnabled {
            controller.add(compiledList)
        }
    }
}
