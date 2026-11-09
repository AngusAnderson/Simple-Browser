import SwiftUI

@MainActor struct LibrarySaveStatus: View {
    
    let store: LibraryStore
    
    var body: some View {
        HStack(spacing: 6) {
            if store.isSaving {
                ProgressView()
                    .controlSize(.mini)
                
                Text("Saving locally...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.errorMessage != nil, store.canWrite {
                Button("Retry Save") {
                    store.retrySave()
                }
                .font(.caption)
            }
        }
    }
}
