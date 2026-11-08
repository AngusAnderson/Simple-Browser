import Foundation

struct BrowserTab: Identifiable {
    let id: UUID
    let session: BrowserSession
    
    @MainActor init(session: BrowserSession) {
        self.id = session.id
        self.session = session
    }
}
