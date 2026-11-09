import Foundation

final class LibraryFileWriter: Sendable {
    private let queue = DispatchQueue(
        label: "browser.library.file-writer",
        qos: .utility
    )

    func write(
        document: LibraryDocument,
        to url: URL,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys
                ]

                let data = try encoder.encode(document)
                try data.write(to: url, options: .atomic)

                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    func waitForPendingWrites() {
        queue.sync {}
    }
}
