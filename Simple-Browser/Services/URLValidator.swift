import Foundation

enum URLValidator {
    static func url(
        from input: String,
        searchEngine: SearchEngine
    ) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return nil
        }

        let lowercased = text.lowercased()

        if lowercased.hasPrefix("https://")
            || lowercased.hasPrefix("http://") {
            return validatedWebURL(from: text)
        }

        let blockedPrefixes = [
            "javascript:",
            "data:",
            "file:",
            "about:",
            "mailto:",
            "tel:"
        ]

        guard !blockedPrefixes.contains(where: {
            lowercased.hasPrefix($0)
        }) else {
            return nil
        }

        if text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return searchEngine.searchURL(for: text)
        }

        if let candidate = validatedWebURL(from: "https://\(text)"),
           let host = candidate.host {
            let isLocalhost = host == "localhost"
                || host.hasSuffix(".localhost")

            if isLocalhost || host.contains(".") || host.contains(":") {
                return candidate
            }
        }

        return searchEngine.searchURL(for: text)
    }

    private static func validatedWebURL(from text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            return nil
        }

        return url
    }

    static func isSecure(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https"
    }
}
