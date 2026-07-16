import SwiftUI
import Charts

struct StockChartView: View {
    private struct StatValue {
        let label: String
        let value: String
        let color: Color
        let helpText: String?
        let showsFundFlowDetail: Bool

        init(
            label: String,
            value: String,
            color: Color,
            helpText: String? = nil,
            showsFundFlowDetail: Bool = false
        ) {
            self.label = label
            self.value = value
            self.color = color
            self.helpText = helpText
            self.showsFundFlowDetail = showsFundFlowDetail
        }
    }

    let stock: Stock
    let onClose: () -> Void
    @EnvironmentObject var appState: AppState

    @State private var points: [MinutePoint] = []
    @State private var preClose: Double = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selectedPointId: Int?
    @State private var fundFlowSnapshot: FundFlowSnapshot?
    @State private var fundFlowTrend: [FundFlowMinutePoint] = []
    @State private var sectorSnapshot: SectorSnapshot?
    @State private var fundFlowStockId: String?
    @State private var isFundFlowLoading = false
    @State private var hoveredStatHelp: String?
    @State private var isFundFlowDetailHovered = false
    @State private var intradayLoadedAt: Date?
    @State private var fundFlowLoadedAt: Date?
    @State private var fundFlowTrendLoadedAt: Date?
    @State private var isIntradayRefreshing = false
    @State private var intradaySignal: IntradaySignal?
    @State private var signalStabilizer = IntradaySignalStabilizer()

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

    private var averageLineColor: Color {
        Color.orange.opacity(0.85)
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
            await pollIntraday()
        }
        .task(id: fundFlowTaskId) {
            await pollFundFlow()
        }
        .onChange(of: quote?.price) { _ in
            refreshIntradaySignal()
        }
        .onChange(of: quote?.updateTime) { _ in
            refreshIntradaySignal()
        }
        .onChange(of: appState.effectiveShares(for: stock)) { _ in
            refreshIntradaySignal()
        }
        .onChange(of: appState.manualRefreshToken) { _ in
            guard stock.market == .aStock else { return }
            Task {
                await refreshIntraday(showLoading: false)
                await loadFundFlow()
            }
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
            .fixedSize(horizontal: true, vertical: false)

            if stock.market == .aStock {
                VStack(alignment: .leading, spacing: 1) {
                    Text(sectorSnapshot?.name ?? " ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(sectorSnapshot?.formattedPercent ?? " ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(sectorChangeColor.opacity(0.9))
                        .lineLimit(1)
                }
                .frame(width: 52, alignment: .leading)
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
        let labelPositions = xAxisLabels.map(\.0)
        let isUS = stock.market == .usStock
        let labelY = yMin + (yMax - yMin) * 0.88
        let selected = selectedPoint
        let selectedAverage = selectedAveragePrice
        let selectedAlignment: Alignment = (selected?.id ?? 0) < (fullDayRange.upperBound / 2)
            ? .leading
            : .trailing
        let selectedAnnotationPosition: AnnotationPosition = selected.map { point in
            let upperSafeBoundary = yMin + (yMax - yMin) * 0.72
            return point.price >= upperSafeBoundary ? .bottom : .top
        } ?? .top
        let lowest = lowestPoint
        let lowestAlignment: Alignment = (lowest?.id ?? 0) < (fullDayRange.upperBound / 2)
            ? .leading
            : .trailing
        let shouldShowLowestLabel = lowest.map { low in
            guard let selected else { return true }
            let xSpan = max(fullDayRange.upperBound - fullDayRange.lowerBound, 1)
            let ySpan = max(yMax - yMin, 0.01)
            let horizontalGap = Double(abs(selected.id - low.id)) / Double(xSpan)
            let verticalGap = abs(selected.price - low.price) / ySpan
            return horizontalGap > 0.16 || verticalGap > 0.28
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
                .foregroundStyle(averageLineColor)
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
                .annotation(position: selectedAnnotationPosition, alignment: selectedAlignment, spacing: 4) {
                    selectedAnnotation(point: selected, averagePrice: selectedAverage)
                }
            }
        }
        .chartXScale(domain: fullDayRange)
        .chartYScale(domain: yMin...yMax)
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
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
        let openPrice = points.first?.price ?? 0
        let fundFlow = fundFlowStat
        let turnoverRate = turnoverRateStat
        let volumeRatio = volumeRatioStat
        let intradaySignal = intradaySignalStat
        let primaryStats: [StatValue?] = [
            StatValue(label: "昨收", value: fmt(preClose), color: .primary),
            StatValue(label: "今开", value: fmt(openPrice), color: openPriceColor(openPrice)),
            StatValue(label: "最高", value: fmt(prices.max() ?? 0), color: .primary),
            StatValue(label: "最低", value: fmt(prices.min() ?? 0), color: .primary),
            fundFlow,
        ]
        let secondaryStats: [StatValue?] = [
            StatValue(
                label: "当前均价",
                value: averagePoints.last.map { fmt($0.price) } ?? "--",
                color: averageLineColor
            ),
            turnoverRate,
            volumeRatio,
            StatValue(
                label: "振幅",
                value: formattedPercent(fundFlowSnapshot?.amplitude),
                color: .primary
            ),
            intradaySignal,
        ]

        return VStack(spacing: 4) {
            statAnchorRow(primaryStats)

            if stock.market == .aStock {
                statAnchorRow(secondaryStats)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func statAnchorRow(_ values: [StatValue?]) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let edgeInset = min(18.0, width / 2)
            let availableWidth = max(0, width - edgeInset * 2)

            ZStack(alignment: .topLeading) {
                ForEach(values.indices, id: \.self) { index in
                    if let item = values[index] {
                        statItemView(item)
                            .fixedSize()
                            .position(
                                x: edgeInset + availableWidth * CGFloat(index) / CGFloat(values.count - 1),
                                y: height / 2
                            )
                    }
                }
            }
        }
        .frame(height: 26)
    }

    @ViewBuilder
    private func statItemView(_ item: StatValue) -> some View {
        if item.showsFundFlowDetail {
            statItem(label: item.label, value: item.value, valueColor: item.color)
                .frame(width: 58, height: 26)
                .contentShape(Rectangle())
                .onHover { isFundFlowDetailHovered = $0 }
                .overlay(alignment: .bottomTrailing) {
                    if isFundFlowDetailHovered {
                        fundFlowDetailCard
                            .fixedSize(horizontal: true, vertical: true)
                            .offset(y: -30)
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(isFundFlowDetailHovered ? 20 : 0)
        } else if let helpText = item.helpText {
            let tooltipAlignment: Alignment = item.label == "盘面" ? .topTrailing : .top
            let tooltipOffset = -CGFloat(helpText.split(separator: "\n").count * 12 + 12)
            statItem(label: item.label, value: item.value, valueColor: item.color)
                .frame(width: 58, height: 26)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    if isHovering {
                        hoveredStatHelp = helpText
                    } else if hoveredStatHelp == helpText {
                        hoveredStatHelp = nil
                    }
                }
                .overlay(alignment: tooltipAlignment) {
                    if hoveredStatHelp == helpText {
                        Text(helpText)
                            .font(.system(size: 9))
                            .multilineTextAlignment(.center)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                            .offset(y: tooltipOffset)
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(hoveredStatHelp == helpText ? 10 : 0)
        } else {
            statItem(label: item.label, value: item.value, valueColor: item.color)
        }
    }

    private func openPriceColor(_ openPrice: Double) -> Color {
        guard openPrice > 0, preClose > 0 else { return .primary }
        if openPrice > preClose { return Color(appState.config.upColorName) }
        if openPrice < preClose { return Color(appState.config.downColorName) }
        return .primary
    }

    private var fundFlowStat: StatValue {
        guard stock.market == .aStock else {
            return StatValue(label: "资金", value: "--", color: .secondary)
        }
        guard let snapshot = fundFlowSnapshot else {
            return StatValue(label: "资金", value: "--", color: .secondary)
        }

        let amount = snapshot.mainNetInflow
        if amount > 0 {
            return StatValue(
                label: "净流入",
                value: formattedFundAmount(amount),
                color: Color(appState.config.upColorName),
                showsFundFlowDetail: true
            )
        }
        if amount < 0 {
            return StatValue(
                label: "净流出",
                value: formattedFundAmount(abs(amount)),
                color: Color(appState.config.downColorName),
                showsFundFlowDetail: true
            )
        }
        return StatValue(
            label: "净流入",
            value: formattedFundAmount(0),
            color: .secondary,
            showsFundFlowDetail: true
        )
    }

    @ViewBuilder
    private var fundFlowDetailCard: some View {
        if let snapshot = fundFlowSnapshot {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("资金流向")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    if !snapshot.updateTime.isEmpty {
                        Text(String(snapshot.updateTime.suffix(8)))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                fundFlowBreakdownTable(snapshot.orderFlows)

                Divider()

                Text("主力分时净流向（30分钟）")
                    .font(.system(size: 9, weight: .medium))

                fundFlowPeriodChart
            }
            .padding(6)
            .frame(width: 296)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
    }

    private func fundFlowBreakdownTable(_ flows: [FundFlowOrderSnapshot]) -> some View {
        VStack(spacing: 0) {
            fundFlowTableHeader
                .background(Color.secondary.opacity(0.10))

            ForEach(flows) { flow in
                Divider()
                fundFlowTableRow(flow)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var fundFlowTableHeader: some View {
        HStack(spacing: 0) {
            fundFlowTableCell("类型", width: 40, alignment: .leading)
            fundFlowTableCell("流入", width: 56)
            fundFlowTableCell("流出", width: 56)
            fundFlowTableCell("净额", width: 80)
            fundFlowTableCell("净占比", width: 52)
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: 18)
    }

    private func fundFlowTableRow(_ flow: FundFlowOrderSnapshot) -> some View {
        HStack(spacing: 0) {
            fundFlowTableCell(flow.size.rawValue, width: 40, alignment: .leading)
                .foregroundStyle(.primary)
            fundFlowTableCell(formattedOptionalFundAmount(flow.inflow), width: 56)
                .foregroundStyle(Color(appState.config.upColorName))
            fundFlowTableCell(formattedOptionalFundAmount(flow.outflow), width: 56)
                .foregroundStyle(Color(appState.config.downColorName))
            fundFlowTableCell(fundFlowNetText(flow.netInflow), width: 80)
                .foregroundStyle(fundFlowAmountColor(flow.netInflow))
            fundFlowTableCell(formattedSignedPercent(flow.netRatio), width: 52)
                .foregroundStyle(fundFlowAmountColor(flow.netRatio))
        }
        .font(.system(size: 8, design: .monospaced))
        .frame(height: 18)
    }

    private func fundFlowTableCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .trailing
    ) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 2)
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    private var fundFlowPeriodChart: some View {
        let periods = FundFlowService.aggregateMainFundFlowByThirtyMinutes(fundFlowTrend)
        if periods.isEmpty {
            Text("暂无分时资金数据")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
        } else {
            let maxMagnitude = max(periods.map { abs($0.netInflow) }.max() ?? 0, 1)
            Chart {
                RuleMark(y: .value("零轴", 0))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 0.6))

                ForEach(periods) { period in
                    BarMark(
                        x: .value("时段", period.startTime),
                        y: .value("净流向", period.netInflow)
                    )
                    .foregroundStyle(fundFlowAmountColor(period.netInflow))
                    .cornerRadius(1.5)
                    .annotation(
                        position: period.netInflow >= 0 ? .top : .bottom,
                        spacing: 1
                    ) {
                        Text(formattedSignedFundAmount(period.netInflow))
                            .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(fundFlowAmountColor(period.netInflow))
                            .fixedSize()
                    }
                }
            }
            .chartYScale(domain: (-maxMagnitude * 1.32)...(maxMagnitude * 1.32))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: periods.map(\.startTime)) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label.hasPrefix("0") ? String(label.dropFirst()) : label)
                                .font(.system(size: 6.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 84)
        }
    }

    private func formattedOptionalFundAmount(_ amount: Double?) -> String {
        guard let amount else { return "--" }
        return formattedFundAmount(amount)
    }

    private func fundFlowNetText(_ amount: Double?) -> String {
        guard let amount else { return "--" }
        if amount > 0 { return "净流入\(formattedFundAmount(amount))" }
        if amount < 0 { return "净流出\(formattedFundAmount(amount))" }
        return "净流入0"
    }

    private func formattedSignedFundAmount(_ amount: Double) -> String {
        if amount > 0 { return "+\(formattedFundAmount(amount))" }
        if amount < 0 { return "-\(formattedFundAmount(amount))" }
        return "0"
    }

    private func formattedSignedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        let sign = value > 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", value)
    }

    private func fundFlowAmountColor(_ amount: Double?) -> Color {
        guard let amount else { return .secondary }
        if amount > 0 { return Color(appState.config.upColorName) }
        if amount < 0 { return Color(appState.config.downColorName) }
        return .secondary
    }

    private var intradaySignalStat: StatValue {
        guard let signal = intradaySignal else {
            return StatValue(
                label: "盘面",
                value: "数据/等待",
                color: .secondary,
                helpText: "盘面：数据\n操作倾向：等待\n操作仅供盘面参考"
            )
        }
        return StatValue(
            label: "盘面",
            value: signal.displayText,
            color: intradaySignalColor(signal.colorRole),
            helpText: signal.helpText
        )
    }

    private func intradaySignalColor(_ role: IntradaySignalColorRole) -> Color {
        switch role {
        case .up: return Color(appState.config.upColorName)
        case .down: return Color(appState.config.downColorName)
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    private var volumeRatioStat: StatValue {
        guard let ratio = fundFlowSnapshot?.volumeRatio, ratio >= 0 else {
            return StatValue(label: "量比", value: "--", color: .secondary, helpText: "暂无量比数据")
        }

        let level = VolumeRatioLevel(ratio: ratio)
        return StatValue(
            label: "量比",
            value: level.displayName,
            color: volumeRatioColor(level),
            helpText: String(
                format: "量比 %.2fx\n当前平均每分钟成交量约为近 5 日平均的 %.2f 倍",
                ratio,
                ratio
            )
        )
    }

    private var turnoverRateStat: StatValue {
        guard let rate = fundFlowSnapshot?.turnoverRate, rate >= 0 else {
            return StatValue(
                label: "换手率",
                value: "--",
                color: .secondary,
                helpText: "暂无换手率数据"
            )
        }

        let level = TurnoverRateLevel(rate: rate)
        return StatValue(
            label: "换手率",
            value: formattedPercent(rate),
            color: turnoverRateColor(level),
            helpText: String(
                format: "换手率 %.2f%%\n累计成交量约为流通股本的 %.2f%%\n属于%@",
                rate,
                rate,
                level.displayName
            )
        )
    }

    private func turnoverRateColor(_ level: TurnoverRateLevel) -> Color {
        switch level {
        case .quiet: return .secondary
        case .low: return .blue
        case .normal: return .green
        case .active: return .orange
        case .high: return .purple
        case .extreme: return .red
        }
    }

    private func volumeRatioColor(_ level: VolumeRatioLevel) -> Color {
        switch level {
        case .quiet: return .secondary
        case .low: return .blue
        case .normal: return .green
        case .active: return .orange
        case .high: return .purple
        case .extreme: return .red
        }
    }

    private var sectorChangeColor: Color {
        guard let changePercent = sectorSnapshot?.changePercent else { return .secondary }
        if changePercent > 0 { return Color(appState.config.upColorName) }
        if changePercent < 0 { return Color(appState.config.downColorName) }
        return .secondary
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
                    .foregroundColor(averageLineColor)
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

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f%%", value)
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

    private func pollIntraday() async {
        intradayLoadedAt = nil
        intradaySignal = nil
        signalStabilizer.reset()
        await refreshIntraday(showLoading: true)

        guard stock.market == .aStock else { return }
        while !Task.isCancelled {
            let interval = max(1, appState.refreshInterval)
            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } catch {
                return
            }
            await refreshIntraday(showLoading: false)
        }
    }

    private func refreshIntraday(showLoading: Bool) async {
        guard !isIntradayRefreshing else { return }
        isIntradayRefreshing = true
        defer {
            isIntradayRefreshing = false
            if showLoading { isLoading = false }
        }

        if showLoading {
            isLoading = true
            loadFailed = false
            selectedPointId = nil
        }

        do {
            let (pts, pc) = try await ChartService.fetchIntraday(stock: stock)
            guard !Task.isCancelled else { return }
            self.points = pts
            self.preClose = pc > 0 ? pc : (quote?.previousClose ?? 0)
            self.intradayLoadedAt = Date()
            self.loadFailed = false
            refreshIntradaySignal()
        } catch is CancellationError {
            return
        } catch {
            if points.isEmpty {
                loadFailed = true
            }
            logToFile("StockChartView: refresh intraday failed for \(stock.id): \(error)")
        }
    }

    private func pollFundFlow() async {
        guard stock.market == .aStock else { return }
        if fundFlowStockId != stock.id {
            fundFlowSnapshot = nil
            fundFlowTrend = []
            sectorSnapshot = nil
            fundFlowLoadedAt = nil
            fundFlowTrendLoadedAt = nil
            isFundFlowDetailHovered = false
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

        let shouldFetchTrend = fundFlowTrendLoadedAt.map {
            Date().timeIntervalSince($0) >= 30
        } ?? true
        async let nextFundFlow = fetchFundFlowSnapshot()
        async let nextTrend = fetchFundFlowTrendIfNeeded(shouldFetchTrend)
        async let nextSectors = fetchSectorSnapshots()
        let (fundFlow, trend, sectors) = await (nextFundFlow, nextTrend, nextSectors)

        guard !Task.isCancelled else { return }
        if let fundFlow {
            fundFlowSnapshot = fundFlow
            fundFlowLoadedAt = Date()
        }
        if let trend {
            fundFlowTrend = trend
            fundFlowTrendLoadedAt = Date()
        }
        if let sectors {
            let primarySectorName = fundFlow?.primarySectorName ?? fundFlowSnapshot?.primarySectorName
            sectorSnapshot = FundFlowService.primarySector(
                from: sectors,
                matching: primarySectorName
            )
        }
        refreshIntradaySignal()
    }

    private func refreshIntradaySignal(now: Date = Date()) {
        guard stock.market == .aStock else { return }
        let input = IntradaySignalInput(
            points: points,
            currentPrice: quote?.price,
            quoteIsToday: quote?.isToday ?? false,
            preClose: preClose > 0 ? preClose : (quote?.previousClose ?? 0),
            volumeRatio: fundFlowSnapshot?.volumeRatio,
            mainNetInflow: fundFlowSnapshot?.mainNetInflow,
            sectorChangePercent: sectorSnapshot?.changePercent,
            isHolding: (appState.effectiveShares(for: stock) ?? 0) > 0,
            now: now,
            intradayLoadedAt: intradayLoadedAt,
            fundFlowLoadedAt: fundFlowLoadedAt,
            fundFlowMaxAge: TimeInterval(max(1, appState.config.fundFlowRefreshInterval * 2))
        )
        let candidate = IntradaySignalService.evaluate(input)
        var stabilizer = signalStabilizer
        intradaySignal = stabilizer.update(candidate)
        signalStabilizer = stabilizer
    }

    private func fetchFundFlowSnapshot() async -> FundFlowSnapshot? {
        do {
            return try await FundFlowService.fetchAStockFundFlow(stock: stock)
        } catch is CancellationError {
            return nil
        } catch {
            logToFile("StockChartView: load fund flow failed for \(stock.id): \(error)")
            return nil
        }
    }

    private func fetchFundFlowTrendIfNeeded(_ shouldFetch: Bool) async -> [FundFlowMinutePoint]? {
        guard shouldFetch else { return nil }
        do {
            return try await FundFlowService.fetchAStockFundFlowTrend(stock: stock)
        } catch is CancellationError {
            return nil
        } catch {
            logToFile("StockChartView: load fund flow trend failed for \(stock.id): \(error)")
            return nil
        }
    }

    private func fetchSectorSnapshots() async -> [SectorSnapshot]? {
        do {
            return try await FundFlowService.fetchAStockSectors(stock: stock)
        } catch is CancellationError {
            return nil
        } catch {
            logToFile("StockChartView: load sector failed for \(stock.id): \(error)")
            return nil
        }
    }
}
