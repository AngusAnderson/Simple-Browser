import SwiftUI
import WebKit

@MainActor
struct WebsiteDataView: View {
    let controller: BrowserController

    @State private var manager: WebsiteDataManager
    @State private var selection = Set<UUID>()

    @Environment(\.dismiss)
    private var dismiss

    init(
        controller: BrowserController,
        store: WKWebsiteDataStore,
        isPrivate: Bool
    ) {
        self.controller = controller

        _manager = State(
            initialValue: WebsiteDataManager(
                store: store,
                isPrivate: isPrivate
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(
                    manager.isPrivate
                        ? "Private Website Data"
                        : "Normal Website Data"
                )
                .font(.title2)

                Spacer()

                Button("Refresh") {
                    selection.removeAll()

                    Task {
                        await manager.refresh()
                    }
                }
                .disabled(manager.isLoading)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("""
            This lists WebKit data records, not a browsing-history \
            or permission list. Deletion closes every tab of this mode \
            and cancels its downloads.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            if manager.isLoading {
                ProgressView("Reading website data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(manager.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name)

                            Text(row.categories)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .tag(row.id)
                    }
                }
            }

            HStack {
                Button("Delete Selected…") {
                    let records = manager.rows
                        .filter { selection.contains($0.id) }
                        .map(\.record)

                    controller.requestWebsiteDataReset(
                        isPrivate: manager.isPrivate,
                        records: records,
                        selectedStore: manager.store
                    )

                    if controller.isClearingData {
                        dismiss()
                    }
                }
                .disabled(selection.isEmpty || manager.isLoading)

                Spacer()

                Button("Clear This Mode…") {
                    controller.requestWebsiteDataReset(
                        isPrivate: manager.isPrivate,
                        selectedStore: manager.store
                    )

                    if controller.isClearingData {
                        dismiss()
                    }
                }
                .disabled(manager.isLoading)
            }
        }
        .padding()
        .frame(width: 760, height: 500)
        .task {
            await manager.refresh()
        }
    }
}
