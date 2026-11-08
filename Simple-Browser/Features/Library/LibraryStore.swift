import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var document = LibraryDocument()
    private(set) var errorMessage: String?
    private(set) var canWrite = false

    @ObservationIgnored
    private var fileURL: URL?

    var bookmarks: [Bookmark] {
        document.bookmarks
    }

    var history: [HistoryEntry] {
        document.history
    }

    var savedTabs: [SavedTab] {
        document.normalTabs
    }

    init() {
        do {
            let manager = FileManager.default

            let support = try manager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let folder = support.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "SimpleBrowser",
                isDirectory: true
            )

            try manager.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            let url = folder.appendingPathComponent("library.json")
            fileURL = url

            if manager.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let loaded = try JSONDecoder().decode(
                    LibraryDocument.self,
                    from: data
                )

                guard loaded.version == 1 else {
                    throw StoreError.unsupportedVersion
                }

                document = loaded
            }

            document.bookmarks.removeAll {
                !Self.isWebURL($0.url)
            }

            document.history.removeAll {
                !Self.isWebURL($0.url)
            }

            document.normalTabs.removeAll {
                !Self.isWebURL($0.url)
            }

            pruneHistory()
            canWrite = true
        } catch {
            errorMessage = """
            Could not open the local browser library: \
            \(error.localizedDescription)

            The existing file has not been overwritten.
            """
        }
    }

    func addBookmark(title: String, url: URL) {
        guard canWrite, Self.isWebURL(url) else { return }

        guard !document.bookmarks.contains(where: {
            $0.url == url
        }) else {
            return
        }

        document.bookmarks.insert(
            Bookmark(title: title, url: url),
            at: 0
        )
    }

    func removeBookmark(id: UUID) {
        guard canWrite else { return }
        document.bookmarks.removeAll { $0.id == id }
    }

    func recordVisit(title: String, url: URL) {
        guard canWrite, Self.isWebURL(url) else { return }

        document.history.insert(
            HistoryEntry(title: title, url: url),
            at: 0
        )

        pruneHistory()
    }

    func removeHistoryEntry(id: UUID) {
        guard canWrite else { return }
        document.history.removeAll { $0.id == id }
    }

    func clearHistory() {
        guard canWrite else { return }
        document.history.removeAll()
    }

    func setSavedTabs(_ tabs: [SavedTab]) {
        guard canWrite else { return }

        document.normalTabs = tabs.filter {
            Self.isWebURL($0.url)
        }
    }

    func save() {
        guard canWrite, let fileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)

            errorMessage = nil
        } catch {
            errorMessage = """
            Changes could not be saved: \(error.localizedDescription)
            """
        }
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return false
        }

        return true
    }

    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        document.history = Array(
            document.history
                .filter { $0.visitedAt >= cutoff }
                .sorted { $0.visitedAt > $1.visitedAt }
                .prefix(500)
        )
    }

    private enum StoreError: LocalizedError {
        case unsupportedVersion

        var errorDescription: String? {
            "This library was created by an unsupported app version."
        }
    }
}
