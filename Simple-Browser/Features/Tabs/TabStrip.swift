import SwiftUI

@MainActor struct TabStrip: View {
    
    let controller: BrowserController
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(controller.tabs) { tab in
                    HStack(spacing: 8) {
                        Button {
                            controller.selectTab(tab.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(
                                    systemName: tab.session.isPrivate ? "eye.slash" : "globe"
                                )
                                
                                Text(tab.session.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: 160, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            controller.closeTab(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close tab")
                    }
                    .padding(8)
                    .background(
                        controller.selectedTabID == tab.id
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.08)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(8)
        }
        .disabled(controller.isClearingData)
    }
}
