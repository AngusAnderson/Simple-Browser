import Foundation

struct TabPersistenceCandidate {
    let url: URL?
    let isPrivate: Bool
}

enum BrowserPrivacyPolicy {
    static func shouldRecordHistory(
        enabled: Bool,
        isPrivate: Bool
    ) -> Bool {
        enabled && !isPrivate
    }
    
    static func shouldRetainPrivateStore(
        isPrivate: Bool,
        selectedRecordsOnly: Bool
    ) -> Bool {
        isPrivate && selectedRecordsOnly
    }
    
    static func restorableTabs(
        from candidates: [TabPersistenceCandidate],
        enabled: Bool
    ) -> [SavedTab] {
        guard enabled else { return [] }
        
        return candidates.compactMap { candidate in
            guard !candidate.isPrivate,
                  let url = candidate.url,
                  isPersitenceWebURL(url) else {
                return nil
            }
            
            return SavedTab(url: url)
        }
    }
    
    private static func isPersitenceWebURL(_ url: URL) -> Bool {
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
}
