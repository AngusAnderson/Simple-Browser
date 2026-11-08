import Foundation

enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case duckduckgo
    case startpage
    case google
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .duckduckgo: "DuckDuckGo"
        case .startpage: "Startpage"
        case .google: "Google"
        }
    }
    
    var searchURLTemplate: String {
        switch self {
        case .duckduckgo: "https://duckduckgo.com/?q=%@"
        case .startpage: "https://www.startpage.com/sp/search?query=%@"
        case .google: "https://www.google.com/search?q=%@"
        }
    }
    
    func searchURL(for query: String) -> URL? {
        let baseURL: String
        let parameterName: String

        switch self {
        case .duckduckgo:
            baseURL = "https://duckduckgo.com/"
            parameterName = "q"

        case .startpage:
            baseURL = "https://www.startpage.com/sp/search"
            parameterName = "query"

        case .google:
            baseURL = "https://www.google.com/search"
            parameterName = "q"
        }

        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: parameterName, value: query)
        ]

        return components.url
    }
}
