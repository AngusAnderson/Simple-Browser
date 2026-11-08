//import Testing
//
//struct URLValidatorTests {
//    @Test func normalisesDomainToHTTPS() {
//        let url = URLValidator.url(
//            from: "example.com",
//            searchEngine: .duckduckgo
//        )
//
//        #expect(url?.absoluteString == "https://example.com/")
//    }
//
//    @Test func preservesExplicitHTTPS() {
//        let url = URLValidator.url(
//            from: "https://developer.apple.com",
//            searchEngine: .duckduckgo
//        )
//
//        #expect(url?.absoluteString == "https://developer.apple.com/")
//    }
//
//    @Test func searchesUnknownText() {
//        let url = URLValidator.url(
//            from: "swift concurrency",
//            searchEngine: .duckduckgo
//        )
//
//        #expect(
//            url?.absoluteString == "https://duckduckgo.com/?q=swift%20concurrency"
//        )
//    }
//
//    @Test func blocksJavaScriptScheme() {
//        let url = URLValidator.url(
//            from: "javascript:alert(1)",
//            searchEngine: .duckduckgo
//        )
//
//        #expect(url == nil)
//    }
//
//    @Test func allowsLocalhost() {
//        let url = URLValidator.url(
//            from: "localhost:8080",
//            searchEngine: .duckduckgo
//        )
//
//        #expect(url?.host == "localhost")
//    }
//}
