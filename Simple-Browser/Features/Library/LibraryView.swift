import SwiftUI

@MainActor struct LibraryView: View {
    let controller: BrowserController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Browser Library")
                    .font(.title2)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            TabView {
                bookmarks
                    .tabItem {
                        Label("Bookmarks", systemImage: "bookmark")
                    }

                history
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
            }
        }
        .padding()
        .frame(width: 680, height: 480)
    }

    private var bookmarks: some View {
        List {
            if controller.library.bookmarks.isEmpty {
                Text("No bookmarks saved.")
                    .foregroundStyle(.secondary)
            }

            ForEach(controller.library.bookmarks) { bookmark in
                HStack {
                    Button {
                        controller.open(bookmark.url)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.title)

                            Text(bookmark.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        controller.removeBookmark(bookmark.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!controller.library.canWrite)
                    .accessibilityLabel("Delete bookmark")
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(
                    controller.preferences.historyEnabled
                        ? "Normal visits: up to 30 days / 500 entries."
                        : "History recording is off."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Clear Saved History…") {
                    controller.clearHistory()
                }
                .disabled(
                    controller.library.history.isEmpty
                        || !controller.library.canWrite
                )
            }
            .padding(.horizontal)

            List {
                ForEach(controller.library.history) { entry in
                    HStack {
                        Button {
                            controller.open(entry.url)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)

                                Text(entry.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text(
                                    entry.visitedAt,
                                    format: .dateTime
                                        .day()
                                        .month()
                                        .hour()
                                        .minute()
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            controller.removeHistoryEntry(entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(!controller.library.canWrite)
                        .accessibilityLabel("Delete history entry")
                    }
                }
            }
        }
    }
}
