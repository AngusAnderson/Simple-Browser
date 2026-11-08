import SwiftUI

@main struct BrowserApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
        .defaultSize(width: 1100, height: 750)
    }
}
