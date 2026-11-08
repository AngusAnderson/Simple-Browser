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

    func searchURL(for query: String) -> URL? {
        let baseURL: String
        let parameter: String

        switch self {
        case .duckduckgo:
            baseURL = "https://duckduckgo.com/"
            parameter = "q"

        case .startpage:
            baseURL = "https://www.startpage.com/sp/search"
            parameter = "query"

        case .google:
            baseURL = "https://www.google.com/search"
            parameter = "q"
        }

        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: parameter, value: query)
        ]

        return components.url
    }
}
