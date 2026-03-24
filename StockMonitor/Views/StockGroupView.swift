import SwiftUI

struct StockGroupView: View {
    let market: Market
    let stocks: [Stock]
    var title: String? = nil
    var onSelect: ((Stock) -> Void)? = nil
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                    Text(title ?? market.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                    Text("(\(stocks.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if isExpanded {
                ForEach(stocks) { stock in
                    StockRowView(stock: stock, quote: appState.quotes[stock.id],
                                 onTap: { onSelect?(stock) })
                        .id(stock.id)
                }
            }
        }
    }
}
