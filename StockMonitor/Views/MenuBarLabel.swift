import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            if let stock = appState.statusBarStock,
               let quote = appState.statusBarQuote {
                Text(quote.formattedPrice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(appState.quoteColor(for: quote))
                Text(quote.formattedPercent)
                    .font(.system(size: 11))
                    .foregroundColor(appState.quoteColor(for: quote))
                if appState.hasPnLData {
                    Text("|")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    let pnl = appState.totalPnL
                    Text(pnl >= 0
                         ? "+\(String(format: "%.0f", pnl))"
                         :   "\(String(format: "%.0f", pnl))")
                        .font(.system(size: 11))
                        .foregroundColor(appState.pnlColor(pnl))
                }
                if appState.hasError {
                    Text("⚠").font(.system(size: 11)).foregroundColor(.yellow)
                }
            }
        }
    }
}
