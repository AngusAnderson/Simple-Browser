import Foundation

enum NavigationDecision: Equatable {
    case allow
    case confirmHTTP
    case confirmExternalApplication
    case block
}

enum NavigationPolicy {
    static func decision(for url: URL) -> NavigationDecision {
        switch url.scheme?.lowercased() {
        case "https":
            return url.host == nil ? .block : .allow
            
        case "http":
            return url.host == nil ? .block : .confirmHTTP
            
        case "about":
            return url.absoluteString == "about:blank" ? .allow : .block
            
        case "mailto", "tel":
            return .confirmExternalApplication
            
        default:
            return .block
        }
    }
}
