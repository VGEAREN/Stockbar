import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool
    @Binding var sortByChange: Bool

    var body: some View {
        HStack {
            Button {
                appState.forceRefresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoading)

            Spacer()

            Button { sortByChange.toggle() } label: {
                Label("排序", systemImage: sortByChange ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    .font(.system(size: 12))
                    .foregroundColor(sortByChange ? .accentColor : .primary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { showSettings = true } label: {
                Label("设置", systemImage: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain)

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                Label("退出", systemImage: "xmark.circle").font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}
