import Foundation

struct Bookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var createdAt = Date()
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var visitedAt = Date()
}

struct SavedTab: Codable, Equatable {
    var url: URL
}

struct LibraryDocument: Codable {
    var version = 1
    var bookmarks: [Bookmark] = []
    var history: [HistoryEntry] = []
    var normalTabs: [SavedTab] = []
}
