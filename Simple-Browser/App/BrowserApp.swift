import SwiftUI

@main struct BrowserApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(minWidth: 950, minHeight: 620)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
    }
}
