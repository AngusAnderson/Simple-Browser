import Foundation

enum AddressResolver {
    static func resolve(
        _ input: String,
        engine: SearchEngine
    ) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else { return nil }
        
        let lower = text.lowercased()
        
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") { return webURL(text) }
        
        let forbiddenPrefixes = [
            "javascript:",
            "data:",
            "file:",
            "about:",
            "mailto:",
            "tel:"
        ]
        
        guard !forbiddenPrefixes.contains(where: lower.hasPrefix) else { return nil }
        
        if text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           let candidate = webURL("https://\(text)"),
           let host = candidate.host {
            let localhost = host == "localhost" || host.hasSuffix(".localhost")
            
            if localhost || host.contains(".") || host.contains(":") { return candidate }
        }
        
        if URLComponents(string: text)?.scheme != nil { return nil }
        
        return engine.searchURL(for: text)
    }
    
    private static func webURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        
        return components.url
    }
}
