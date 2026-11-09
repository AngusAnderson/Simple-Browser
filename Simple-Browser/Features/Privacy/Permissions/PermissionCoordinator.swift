import Foundation
import WebKit

@MainActor enum PermissionCoordinator {
    static func requestMedia(
        origin: WKSecurityOrigin,
        frame: WKFrameInfo,
        type: WKMediaCaptureType,
        topLevelURL: URL?,
        isPrivate: Bool
    ) -> WKPermissionDecision {
        let requestingOrigin = SiteOrigin(origin)
        
        guard requestingOrigin.isHTTPS, topLevelURL?.scheme?.lowercased() == "https" else {
            return .deny
        }
        
        let requestedDevice: String
        
        switch type {
            case .camera: requestedDevice = "camera"
            case .microphone: requestedDevice = "microphone"
            case .cameraAndMicrophone: requestedDevice = "camera and microphone"
                
            @unknown default: return .deny
        }
        
        let frameDescription = frame.isMainFrame
            ? "The main page is requesting access."
            : "An embedded frame is requesting access."
        
        let accepted = NativeDialogs.confirm(
            title: "Allow \(requestedDevice) access?",
            message: """
                Requesting origin:
                \(requestingOrigin.displayName)
                
                Displayed page:
                \(topLevelURL?.host ?? "Unknown")
                
                \(frameDescription)
                
                \(isPrivate ? "This is a private tab." : "This is a normal tab.")
                
                The browser will not save an Always Allow permission.
                MacOS may also ask for permission
                """,
            accept: "Allow"
        )
        
        return accepted ? .grant : .deny
    }
}
