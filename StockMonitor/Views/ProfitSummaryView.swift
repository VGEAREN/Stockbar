import SwiftUI

struct ProfitSummaryView: View {
    @EnvironmentObject var appState: AppState

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        if appState.hasPnLData {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("持仓盈亏").font(.system(size: 10)).foregroundColor(.secondary)
                    if let t = appState.lastUpdateTime {
                        Text("更新：\(Self.timeFmt.string(from: t))\(appState.hasError ? " ⚠" : "")")
                            .font(.system(size: 9))
                            .foregroundColor(appState.hasError ? .yellow : .secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    let daily = appState.totalDailyPnL
                    Text(daily >= 0
                         ? "日+\(String(format: "%.2f", daily))"
                         :  "日\(String(format: "%.2f", daily))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.pnlColor(daily))
                    let pnl = appState.totalPnL
                    Text(pnl >= 0
                         ? "浮+\(String(format: "%.2f", pnl))"
                         :  "浮\(String(format: "%.2f", pnl))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.pnlColor(pnl))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
    }
}
