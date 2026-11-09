import SwiftUI

@MainActor struct DownloadsView: View {
    
    let manager: DownloadManager
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Downloads")
                    .font(.title2)
                
                Spacer()
                
                Button("Clear Finished") {
                    manager.clearFinishedItems()
                }
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            
            if manager.items.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloads appear here during session")
                )
            } else {
                List {
                    ForEach(manager.items) { item in
                        DownloadRow(item: item, manager: manager)
                    }
                }
            }
        }
        .padding()
        .frame(width: 640, height: 420)
    }
}

@MainActor private struct DownloadRow: View {
    
    let item: DownloadItem
    let manager: DownloadManager
    
    var body: some View {
        HStack(spacing: 12) {
            if item.state.isActive {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(
                    systemName: item.state == .completed
                        ? "checkmark.circle"
                        : "arrow.down.circle"
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .lineLimit(1)
                
                Text(
                    item.isPrivate
                        ? "\(item.state.rawValue) • Private"
                        : item.state.rawValue
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if let error = item.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Spacer()
            
            if item.state == .downloading {
                Button("Cancel") { manager.cancel(item) }
            }
            
            if item.state == .completed {
                Button("Show in Finder") { manager.reveal(item) }
            }
        }
        .padding(.vertical, 4)
    }
}
