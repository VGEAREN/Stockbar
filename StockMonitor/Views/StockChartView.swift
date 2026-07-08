import SwiftUI
import Charts

struct StockChartView: View {
    let stock: Stock
    let onClose: () -> Void
    @EnvironmentObject var appState: AppState

    @State private var points: [MinutePoint] = []
    @State private var preClose: Double = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selectedPointId: Int?
    @State private var fundFlowSnapshot: FundFlowSnapshot?
    @State private var fundFlowStockId: String?
    @State private var isFundFlowLoading = false

    private var quote: Quote? { appState.quotes[stock.id] }
    private var fundFlowTaskId: String { "\(stock.id)-\(appState.config.fundFlowRefreshInterval)" }

    private var averagePoints: [MinutePoint] {
        var total = 0.0
        return points.enumerated().map { index, point in
            total += point.price
            return MinutePoint(
                id: point.id,
                time: point.time,
                price: total / Double(index + 1)
            )
        }
    }

    private var selectedPoint: MinutePoint? {
        guard let selectedPointId else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.id - selectedPointId) < abs(rhs.id - selectedPointId)
        }
    }

    private var selectedAveragePrice: Double? {
        guard let selectedPoint else { return nil }
        return averagePoints.first(where: { $0.id == selectedPoint.id })?.price
    }

    private var lowestPoint: MinutePoint? {
        points.reduce(nil) { current, point in
            guard let current else { return point }
            return point.price < current.price ? point : current
        }
    }

    // MARK: - 全天 x 轴范围（按市场）
    // A股：09:30-11:30 + 13:00-15:00 = 240 分钟
    // 港股：09:30-12:00 + 13:00-16:00 = 330 分钟
    // 美股：04:00-20:00 = 960 分钟（含盘前+正常+盘后）
    private var fullDayRange: ClosedRange<Int> {
        switch stock.market {
        case .aStock:  return 0...239
        case .hkStock: return 0...329
        case .usStock: return 0...959
        case .krStock: return 0...389
        }
    }

    // 对应各市场的时间标签（index → 时间字符串）
    private var xAxisLabels: [(Int, String)] {
        switch stock.market {
        case .aStock:
            return [(0, "09:30"), (60, "10:30"), (120, "13:00"), (180, "14:00"), (239, "15:00")]
        case .hkStock:
            return [(0, "09:30"), (75, "10:45"), (150, "13:00"), (240, "15:00"), (329, "16:00")]
        case .usStock:
            // 基准 04:00 ET；330=09:30；720=16:00；959=19:59
            return [(0, "04:00"), (330, "09:30"), (570, "13:30"), (720, "16:00"), (959, "20:00")]
        case .krStock:
            // 基准 09:00 KST；180=12:00；389=15:29
            return [(0, "09:00"), (90, "10:30"), (180, "12:00"), (270, "13:30"), (389, "15:30")]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            chartAreaView
                .frame(height: 200)
            if !isLoading && !loadFailed && !points.isEmpty {
                statsRow
            }
        }
        .task(id: stock.id) {
            await load()
        }
        .task(id: fundFlowTaskId) {
            await pollFundFlow()
        }
        .onChange(of: appState.manualRefreshToken) { _ in
            guard stock.market == .aStock else { return }
            Task { await loadFundFlow() }
        }
    }

    // MARK: - 顶部信息栏

    private var headerView: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if let limits = priceLimits {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("涨停 \(fmt(limits.up))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(appState.config.upColorName))
                    Text("跌停 \(fmt(limits.down))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(appState.config.downColorName))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            if let q = quote {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(q.formattedPrice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(appState.quoteColor(for: q))
                    Text(q.formattedPercent)
                        .font(.system(size: 10))
                        .foregroundColor(appState.quoteColor(for: q))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - 图表区域

    @ViewBuilder
    private var chartAreaView: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed || points.isEmpty {
            Text("暂无分时数据")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            lineChart
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    // 美股时段定义：x 轴 index（基准 04:00 ET，每分钟 +1）
    private let usSessions: [(name: String, start: Int, end: Int, color: Color)] = [
        ("盘前", 0,   329, Color.indigo),
        ("盘中", 330, 719, Color.teal),
        ("盘后", 720, 959, Color.orange),
    ]

    private var lineChart: some View {
        let prices = points.map(\.price)
        let avgPoints = averagePoints
        let avgPrices = avgPoints.map(\.price)
        let referencePrice = preClose > 0 ? preClose : (prices.first ?? 0)
        let allPrices = prices + avgPrices + [referencePrice]
        let minP = allPrices.min() ?? referencePrice
        let maxP = allPrices.max() ?? referencePrice
        let minSpan = max(referencePrice * 0.005, 0.01)
        let maxDev = max(abs(maxP - referencePrice), abs(referencePrice - minP), minSpan)
        let yMin = referencePrice - maxDev * 1.15
        let yMax = referencePrice + maxDev * 1.15

        let lastPrice = prices.last ?? referencePrice
        let lineColor: Color = lastPrice >= referencePrice
            ? Color(appState.config.upColorName)
            : Color(appState.config.downColorName)
        let averageColor = Color.orange.opacity(0.85)

        let labelPositions = xAxisLabels.map(\.0)
        let isUS = stock.market == .usStock
        let labelY = yMin + (yMax - yMin) * 0.88
        let selected = selectedPoint
        let selectedAverage = selectedAveragePrice
        let selectedAlignment: Alignment = (selected?.id ?? 0) < (fullDayRange.upperBound / 2)
            ? .leading
            : .trailing
        let lowest = lowestPoint
        let lowestAlignment: Alignment = (lowest?.id ?? 0) < (fullDayRange.upperBound / 2)
            ? .leading
            : .trailing
        let shouldShowLowestLabel = lowest.map { low in
            guard let selected else { return true }
            return abs(selected.id - low.id) > 12
        } ?? false

        return Chart {
            // 美股时段背景色块
            if isUS {
                ForEach(usSessions, id: \.name) { s in
                    RectangleMark(
                        xStart: .value("xs", s.start),
                        xEnd:   .value("xe", s.end),
                        yStart: .value("ys", yMin),
                        yEnd:   .value("ye", yMax)
                    )
                    .foregroundStyle(s.color.opacity(0.07))
                }
                // 美股时段文字标注
                ForEach(usSessions, id: \.name) { s in
                    PointMark(
                        x: .value("t", (s.start + s.end) / 2),
                        y: .value("price", labelY)
                    )
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Text(s.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(s.color.opacity(0.65))
                    }
                }
            }

            // 昨收参考线
            RuleMark(y: .value("昨收", referencePrice))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                .foregroundStyle(Color.secondary.opacity(0.5))

            // 价格线下方的淡色面积填充
            ForEach(points) { p in
                AreaMark(
                    x: .value("t", p.id),
                    yStart: .value("base", yMin),
                    yEnd: .value("price", p.price),
                    series: .value("series", "填充")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineColor.opacity(0.12))
            }

            // 价格折线
            ForEach(points) { p in
                LineMark(
                    x: .value("t", p.id),
                    y: .value("price", p.price),
                    series: .value("series", "价格")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // 分时均线
            ForEach(avgPoints) { p in
                LineMark(
                    x: .value("t", p.id),
                    y: .value("avg", p.price),
                    series: .value("series", "均线")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(averageColor)
                .lineStyle(StrokeStyle(lineWidth: 1.0))
            }

            if let lowest {
                PointMark(
                    x: .value("最低时间", lowest.id),
                    y: .value("最低价", lowest.price)
                )
                .foregroundStyle(Color(appState.config.downColorName).opacity(0.75))
                .symbolSize(18)
                .annotation(position: .top, alignment: lowestAlignment, spacing: 3) {
                    if shouldShowLowestLabel {
                        lowestAnnotation(point: lowest)
                    }
                }
            }

            if let selected {
                RuleMark(x: .value("选中时间", selected.id))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [2, 2]))

                PointMark(
                    x: .value("选中时间", selected.id),
                    y: .value("选中价格", selected.price)
                )
                .foregroundStyle(lineColor)
                .symbolSize(24)
                .annotation(position: .top, alignment: selectedAlignment, spacing: 4) {
                    selectedAnnotation(point: selected, averagePrice: selectedAverage)
                }
            }
        }
        .chartXScale(domain: fullDayRange)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: labelPositions) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let i = value.as(Int.self),
                       let label = xAxisLabels.first(where: { $0.0 == i })?.1 {
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(
                                    at: value.location,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            }
                    )
            }
        }
    }

    // MARK: - 底部统计
    // 今开：分时第一个点的价格；昨收：API 返回的 preclose

    private var statsRow: some View {
        let prices = points.map(\.price)
        let fundFlow = fundFlowStat
        return HStack(spacing: 0) {
            statItem(label: "昨收", value: fmt(preClose))
            Spacer()
            statItem(label: "今开", value: fmt(points.first?.price ?? 0))
            Spacer()
            statItem(label: "最高", value: fmt(prices.max() ?? 0))
            Spacer()
            statItem(label: "最低", value: fmt(prices.min() ?? 0))
            Spacer()
            statItem(label: fundFlow.label, value: fundFlow.value, valueColor: fundFlow.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var fundFlowStat: (label: String, value: String, color: Color) {
        guard stock.market == .aStock else {
            return ("资金", "--", .secondary)
        }
        guard let snapshot = fundFlowSnapshot else {
            return ("资金", "--", .secondary)
        }

        let amount = snapshot.mainNetInflow
        if amount > 0 {
            return ("净流入", formattedFundAmount(amount), Color(appState.config.upColorName))
        }
        if amount < 0 {
            return ("净流出", formattedFundAmount(abs(amount)), Color(appState.config.downColorName))
        }
        return ("净流入", formattedFundAmount(0), .secondary)
    }

    private func statItem(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(valueColor)
        }
    }

    private func selectedAnnotation(point: MinutePoint, averagePrice: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(formattedTime(point.time))
                .font(.system(size: 9, weight: .semibold))
            Text("价 \(fmt(point.price))")
                .font(.system(size: 9))
            if let averagePrice {
                Text("均 \(fmt(averagePrice))")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.thinMaterial)
        .cornerRadius(5)
    }

    private func lowestAnnotation(point: MinutePoint) -> some View {
        Text("最低时间 \(formattedTime(point.time))")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Color(appState.config.downColorName))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.thinMaterial)
            .cornerRadius(4)
    }

    private var priceLimits: (up: Double, down: Double)? {
        guard preClose > 0, let rate = priceLimitRate else { return nil }
        let up = roundedLimitPrice(preClose * (1 + rate))
        let down = roundedLimitPrice(preClose * (1 - rate))
        return (up, max(down, 0))
    }

    private var priceLimitRate: Double? {
        switch stock.market {
        case .aStock:
            let code = stock.id.lowercased()
            let name = stock.name.uppercased()
            if name.contains("ST") { return 0.05 }
            if code.hasPrefix("sh688") || code.hasPrefix("sz300") || code.hasPrefix("sz301") {
                return 0.20
            }
            if code.hasPrefix("bj") { return 0.30 }
            return 0.10
        case .krStock:
            return 0.30
        case .hkStock, .usStock:
            return nil
        }
    }

    private func roundedLimitPrice(_ value: Double) -> Double {
        switch stock.market {
        case .krStock:
            return value.rounded()
        default:
            return (value * 100).rounded() / 100
        }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard plotFrame.contains(location) else { return }
        let xPosition = location.x - plotFrame.origin.x
        guard let xValue = proxy.value(atX: xPosition, as: Int.self) else { return }
        selectedPointId = nearestPointId(to: xValue)
    }

    private func nearestPointId(to xValue: Int) -> Int? {
        points.min { lhs, rhs in
            abs(lhs.id - xValue) < abs(rhs.id - xValue)
        }?.id
    }

    private func fmt(_ v: Double) -> String {
        // 韩元等大数字（如 284000）用整数显示；港币/美元中等数字 2 位小数；小数价 3 位
        if v >= 1000 { return String(format: "%.0f", v) }
        if v >= 10   { return String(format: "%.2f", v) }
        return String(format: "%.3f", v)
    }

    private func formattedTime(_ raw: String) -> String {
        if raw.contains(":") { return raw }
        let digits = raw.filter(\.isNumber)
        guard digits.count == 4 else { return raw }
        let hour = String(digits.prefix(2))
        let minute = String(digits.suffix(2))
        return "\(hour):\(minute)"
    }

    private func formattedFundAmount(_ amount: Double) -> String {
        let value = abs(amount)
        if value >= 100_000_000 {
            return "\(trimmedNumber(value / 100_000_000, decimals: 2))亿"
        }
        if value >= 10_000 {
            let decimals = value >= 1_000_000 ? 1 : 2
            return "\(trimmedNumber(value / 10_000, decimals: decimals))万"
        }
        return trimmedNumber(value, decimals: 0)
    }

    private func trimmedNumber(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains(".") && text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }

    // MARK: - 数据加载

    private func load() async {
        isLoading = true
        loadFailed = false
        selectedPointId = nil
        do {
            let (pts, pc) = try await ChartService.fetchIntraday(stock: stock)
            self.points = pts
            self.preClose = pc > 0 ? pc : (quote?.previousClose ?? 0)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func pollFundFlow() async {
        guard stock.market == .aStock else { return }
        if fundFlowStockId != stock.id {
            fundFlowSnapshot = nil
            fundFlowStockId = stock.id
        }

        let interval = max(1, appState.config.fundFlowRefreshInterval)

        await loadFundFlow()

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } catch {
                return
            }
            await loadFundFlow()
        }
    }

    private func loadFundFlow() async {
        guard !isFundFlowLoading else { return }
        isFundFlowLoading = true
        defer { isFundFlowLoading = false }

        do {
            if let snapshot = try await FundFlowService.fetchAStockFundFlow(stock: stock) {
                fundFlowSnapshot = snapshot
            }
        } catch is CancellationError {
            return
        } catch {
            logToFile("StockChartView: load fund flow failed for \(stock.id): \(error)")
            return
        }
    }
}
