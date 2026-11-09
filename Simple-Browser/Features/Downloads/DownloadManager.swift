import AppKit
import Foundation
import Observation
import WebKit

@MainActor @Observable final class DownloadManager: NSObject {
    private(set) var items: [DownloadItem] = []

    @ObservationIgnored
    private var transfers: [ObjectIdentifier: Transfer] = [:]

    private struct Transfer {
        let download: WKDownload
        let sourceView: WKWebView
        let item: DownloadItem
        var selectedURL: URL?
    }

    func accept(
        _ download: WKDownload,
        sourceView: WKWebView,
        isPrivate: Bool
    ) {
        let key = ObjectIdentifier(download)

        guard transfers[key] == nil else {
            return
        }

        let item = DownloadItem(isPrivate: isPrivate)
        items.insert(item, at: 0)

        transfers[key] = Transfer(
            download: download,
            sourceView: sourceView,
            item: item,
            selectedURL: nil
        )

        download.delegate = self
    }

    func cancel(_ item: DownloadItem) {
        guard let pair = transfers.first(where: {
            $0.value.item.id == item.id
        }) else {
            return
        }

        guard item.state == .downloading else {
            return
        }

        item.state = .cancelling

        let key = pair.key

        pair.value.download.cancel { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish(
                    key: key,
                    state: .cancelled,
                    error: nil
                )
            }
        }
    }

    func reveal(_ item: DownloadItem) {
        guard item.state == .completed,
              let destination = item.destination else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([
            destination
        ])
    }

    func clearFinishedItems() {
        items.removeAll { !$0.state.isActive }
    }

    private func finish(
        key: ObjectIdentifier,
        state: DownloadState,
        error: String?
    ) {
        guard let transfer = transfers.removeValue(forKey: key) else {
            return
        }

        transfer.item.state = state
        transfer.item.errorMessage = error
        transfer.download.delegate = nil

        transfer.selectedURL?.stopAccessingSecurityScopedResource()
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let key = ObjectIdentifier(download)

        guard let transfer = transfers[key] else {
            completionHandler(nil)
            return
        }

        let item = transfer.item

        let suggestedName = (suggestedFilename as NSString)
            .lastPathComponent

        item.filename = suggestedName.isEmpty
            ? "Download"
            : suggestedName

        if item.isPrivate {
            let accepted = NativeDialogs.confirm(
                title: "Save a file from private browsing?",
                message: """
                The downloaded file will remain on this device \
                after private tabs close.

                It will not be opened automatically.
                """,
                accept: "Choose Destination"
            )

            guard accepted else {
                completionHandler(nil)
                finish(key: key, state: .cancelled, error: nil)
                return
            }
        }

        let panel = NSSavePanel()
        panel.title = "Save Download"
        panel.message = """
        Choose a new filename. This version does not overwrite existing files.
        """
        panel.nameFieldStringValue = item.filename
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let destination = panel.url else {
            completionHandler(nil)
            finish(key: key, state: .cancelled, error: nil)
            return
        }

        transfers[key]?.selectedURL = destination

        guard !FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            completionHandler(nil)

            finish(
                key: key,
                state: .failed,
                error: """
                That file already exists. Start the download again \
                and choose a different filename.
                """
            )
            return
        }

        item.filename = destination.lastPathComponent
        item.destination = destination
        item.state = .downloading

        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(
            key: ObjectIdentifier(download),
            state: .completed,
            error: nil
        )
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        let key = ObjectIdentifier(download)

        guard let transfer = transfers[key] else {
            return
        }

        let nsError = error as NSError

        let cancelled = transfer.item.state == .cancelling
            || (
                nsError.domain == NSURLErrorDomain
                && nsError.code == NSURLErrorCancelled
            )

        finish(
            key: key,
            state: cancelled ? .cancelled : .failed,
            error: cancelled ? nil : error.localizedDescription
        )
    }

    func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
    ) {
        guard let scheme = request.url?.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(scheme == "https" ? .allow : .cancel)
    }
}
