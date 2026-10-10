import SwiftUI

struct MiniIntradayChartView: View {
    let market: Market
    let snapshot: IntradayChartSnapshot?
    let quote: Quote?
    let upColor: Color
    let downColor: Color

    private var validPoints: [MinutePoint] {
        snapshot?.points.filter { $0.price.isFinite && $0.price > 0 } ?? []
    }

    private var baselinePrice: Double? {
        if let preClose = snapshot?.preClose, preClose > 0 {
            return preClose
        }
        return quote?.previousClose
    }

    private var lineColor: Color {
        guard let lastPrice = validPoints.last?.price ?? quote?.price,
              let baseline = baselinePrice,
              baseline > 0 else {
            return .secondary.opacity(0.65)
        }
        if lastPrice > baseline { return upColor }
        if lastPrice < baseline { return downColor }
        return .secondary.opacity(0.65)
    }

    private var fullDayUpperBound: Int {
        switch market {
        case .aStock: return 239
        case .hkStock: return 329
        case .usStock: return 959
        case .krStock: return 389
        }
    }

    var body: some View {
        Canvas { context, size in
            drawChart(context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawChart(context: inout GraphicsContext, size: CGSize) {
        let points = validPoints
        guard points.count >= 2, size.width > 2, size.height > 2 else { return }

        let prices = points.map(\.price)
        guard var minPrice = prices.min(),
              var maxPrice = prices.max() else { return }

        if let baseline = baselinePrice, baseline > 0 {
            minPrice = min(minPrice, baseline)
            maxPrice = max(maxPrice, baseline)
        }

        let priceRange = maxPrice - minPrice
        let verticalPadding = max(size.height * 0.16, 2)
        let drawableHeight = max(size.height - verticalPadding * 2, 1)
        let xUpperBound = max(fullDayUpperBound, points.map(\.id).max() ?? 1, 1)

        func xPosition(for point: MinutePoint) -> CGFloat {
            let ratio = CGFloat(point.id) / CGFloat(xUpperBound)
            return min(max(ratio * size.width, 0), size.width)
        }

        func yPosition(for price: Double) -> CGFloat {
            guard priceRange > 0 else { return size.height / 2 }
            let ratio = CGFloat((maxPrice - price) / priceRange)
            return verticalPadding + ratio * drawableHeight
        }

        if let baseline = baselinePrice, baseline > 0, priceRange > 0 {
            let baselineY = yPosition(for: baseline)
            var baselinePath = Path()
            baselinePath.move(to: CGPoint(x: 0, y: baselineY))
            baselinePath.addLine(to: CGPoint(x: size.width, y: baselineY))
            context.stroke(
                baselinePath,
                with: .color(.secondary.opacity(0.16)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            )
        }

        var linePath = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: xPosition(for: point), y: yPosition(for: point.price))
            if index == 0 {
                linePath.move(to: position)
            } else {
                linePath.addLine(to: position)
            }
        }

        context.stroke(
            linePath,
            with: .color(lineColor),
            style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
        )
    }
}
