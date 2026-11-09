import SwiftUI

struct BrowserWindowActions {
    let focusAddress: @MainActor () -> Void
    let showLibrary: @MainActor () -> Void
    let showDownloads: @MainActor () -> Void
}

private struct BrowserWindowActionsKey: FocusedValueKey {
    typealias Value = BrowserWindowActions
}

extension FocusedValues {
    var browserWindowActions: BrowserWindowActions? {
        get {
            self[BrowserWindowActionsKey.self]
        } set {
            self[BrowserWindowActionsKey.self] = newValue
        }
    }
}
