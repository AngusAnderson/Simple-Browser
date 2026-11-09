import Foundation
import Observation
import WebKit

struct WebsiteDataRow: Identifiable {
    let id = UUID()
    let record: WKWebsiteDataRecord

    var name: String {
        record.displayName
    }

    var categories: String {
        record.dataTypes.sorted().joined(separator: ", ")
    }
}

@MainActor @Observable final class WebsiteDataManager {
    let store: WKWebsiteDataStore
    let isPrivate: Bool

    private(set) var rows: [WebsiteDataRow] = []
    private(set) var isLoading = false

    init(
        store: WKWebsiteDataStore,
        isPrivate: Bool
    ) {
        self.store = store
        self.isPrivate = isPrivate
    }

    func refresh() async {
        guard !isLoading else {
            return
        }

        isLoading = true

        let records: [WKWebsiteDataRecord] =
            await withCheckedContinuation { continuation in
                store.fetchDataRecords(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
                ) { records in
                    continuation.resume(returning: records)
                }
            }

        rows = records
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
            .map {
                WebsiteDataRow(record: $0)
            }

        isLoading = false
    }

    static func remove(
        records: [WKWebsiteDataRecord]?,
        from store: WKWebsiteDataStore
    ) async {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in

            let types = WKWebsiteDataStore.allWebsiteDataTypes()

            if let records {
                store.removeData(
                    ofTypes: types,
                    for: records,
                    completionHandler: {
                        continuation.resume()
                    }
                )
            } else {
                store.removeData(
                    ofTypes: types,
                    modifiedSince: .distantPast,
                    completionHandler: {
                        continuation.resume()
                    }
                )
            }
        }
    }
}
