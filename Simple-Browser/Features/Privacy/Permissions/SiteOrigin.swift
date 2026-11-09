import Foundation
import WebKit

struct SiteOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init(_ origin: WKSecurityOrigin) {
        scheme = origin.protocol.lowercased()
        host = origin.host.lowercased()

        if origin.port > 0 {
            port = origin.port
        } else {
            port = scheme == "https" ? 443 : 80
        }
    }

    var displayName: String {
        let displayHost = host.contains(":")
            ? "[\(host)]"
            : host

        return "\(scheme)://\(displayHost):\(port)"
    }

    var isHTTPS: Bool {
        scheme == "https" && !host.isEmpty
    }
}
