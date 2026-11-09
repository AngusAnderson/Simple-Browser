import SwiftUI

@main struct BrowserApp: App {
    var body: some Scene {
        Window("Simple Browser", id: "browser") {
            BrowserView()
            // Uncomment for performance testing
//            BrowserPerformanceProbe()
        }
        .defaultSize(width: 1200, height: 800)
    }
}
