import SwiftUI

@MainActor
struct PageLoadProgress: View {
    let session: BrowserSession

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.clear

                if session.isLoading {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width
                                * clampedProgress
                        )
                }
            }
        }
        .frame(height: 2)
        .accessibilityLabel("Page loading progress")
        .accessibilityValue(
            session.isLoading
                ? "\(Int(clampedProgress * 100)) percent"
                : "Finished"
        )
    }

    private var clampedProgress: Double {
        min(max(session.progress, 0), 1)
    }
}
