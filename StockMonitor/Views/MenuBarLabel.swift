import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    private var mode: String { appState.statusBarStockId }

    var body: some View {
        let isPnl = mode == "__daily_pnl__" || mode == "__total_pnl__" || mode == "__both_pnl__"

        HStack(spacing: 4) {
            if appState.isDoNotDisturbActive {
                appIcon
                Text("免打扰中")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else if isPnl {
                pnlText
            } else if let stock = appState.statusBarStock,
                      let quote = appState.statusBarQuote {
                leadingIndicator(for: stock)
                quoteText(for: quote)
                    .foregroundColor(appState.quoteColor(for: quote))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            } else {
                appIcon
            }

            if !appState.isDoNotDisturbActive && appState.hasError {
                Text("⚠").font(.system(size: 11)).foregroundColor(.yellow)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var appIcon: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private func leadingIndicator(for stock: Stock) -> some View {
        switch appState.statusBarIconMode {
        case .appIcon:
            appIcon
        case .stockInitial:
            Image(nsImage: initialBadgeImage(for: stock))
        case .hidden:
            EmptyView()
        }
    }

    private func quoteText(for quote: Quote) -> Text {
        Text(quote.formattedPrice)
            .font(.system(size: 12, weight: .medium))
        + Text(" ")
        + Text(quote.formattedPercent)
            .font(.system(size: 11))
    }

    private func stockInitial(for stock: Stock) -> String {
        let name = stock.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first {
            return String(String(first).uppercased().prefix(1))
        }

        let code = stock.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = code.first {
            return String(String(first).uppercased().prefix(1))
        }

        return "?"
    }

    private func initialBadgeImage(for stock: Stock) -> NSImage {
        let initial = stockInitial(for: stock)
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black.withAlphaComponent(0.85)
        ]
        let textSize = initial.size(withAttributes: attributes)
        let imageSize = NSSize(width: max(14, ceil(textSize.width) + 6), height: 14)

        return NSImage(size: imageSize, flipped: false) { rect in
            NSColor.white.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()

            let textRect = NSRect(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            initial.draw(in: textRect, withAttributes: attributes)
            return true
        }
    }

    /// 拼成一个 Text 显示，避免 @ViewBuilder 多分支问题
    private var pnlText: Text {
        guard appState.hasPnLData else {
            return Text("--").font(.system(size: 11)).foregroundColor(.secondary)
        }
        let sym = appState.displayCurrency.symbol
        var parts: [Text] = []

        if mode == "__daily_pnl__" || mode == "__both_pnl__" {
            let d = appState.totalDailyPnL
            let s = "日\(d >= 0 ? "+" : "")\(sym)\(String(format: "%.0f", d))"
            parts.append(Text(s).foregroundColor(appState.pnlColor(d)))
        }
        if mode == "__total_pnl__" || mode == "__both_pnl__" {
            let p = appState.totalPnL
            let s = "浮\(p >= 0 ? "+" : "")\(sym)\(String(format: "%.0f", p))"
            parts.append(Text(s).foregroundColor(appState.pnlColor(p)))
        }

        let combined = parts.enumerated().reduce(Text("")) { result, item in
            item.offset == 0 ? item.element : result + Text(" ") + item.element
        }
        return combined.font(.system(size: 11, weight: .medium))
    }
}
