import Foundation
import Observation

enum DownloadState: String {
    case choosingDestination = "Choose destination"
    case downloading = "Downloading"
    case cancelling = "Cancelling"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case failed = "Failed"
    
    var isActive: Bool {
        switch self {
            case .choosingDestination, .downloading, .cancelling: true
            case .completed, .cancelled, .failed: false
        }
    }
}

@MainActor @Observable final class DownloadItem: Identifiable {
    let id = UUID()
    let isPrivate: Bool
    
    var filename = "Download"
    var state: DownloadState = .choosingDestination
    var destination: URL?
    var errorMessage: String?
    
    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
    }
}
