import SwiftUI

@main @MainActor struct BrowserApp: App {
    @State private var controller = BrowserController()
    
    var body: some Scene {
        Window("Simple Browsera", id: "browser") {
            BrowserView(controller: controller)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            BrowserCommands(controller: controller)
        }
        
        Settings {
            BrowserSettingsView(controller: controller)
        }
    }
}
