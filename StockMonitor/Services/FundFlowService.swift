import Foundation

enum FundFlowOrderSize: String, CaseIterable, Equatable {
    case superLarge = "超大单"
    case large = "大单"
    case medium = "中单"
    case small = "小单"
}

struct FundFlowOrderSnapshot: Equatable, Identifiable {
    let size: FundFlowOrderSize
    let inflow: Double?
    let outflow: Double?
    let netInflow: Double?
    let netRatio: Double?

    var id: FundFlowOrderSize { size }
}

struct FundFlowSnapshot {
    let mainNetInflow: Double
    let orderFlows: [FundFlowOrderSnapshot]
    let turnoverRate: Double?
    let volumeRatio: Double?
    let amplitude: Double?
    let updateTime: String
    let primarySectorName: String?
}

struct FundFlowMinutePoint: Equatable, Identifiable {
    let time: String
    let mainNetInflow: Double
    let smallNetInflow: Double
    let mediumNetInflow: Double
    let largeNetInflow: Double
    let superLargeNetInflow: Double

    var id: String { time }
}

struct FundFlowPeriodSnapshot: Equatable, Identifiable {
    let startTime: String
    let endTime: String
    let netInflow: Double

    var id: String { startTime }
}

enum TurnoverRateLevel: Equatable {
    case quiet
    case low
    case normal
    case active
    case high
    case extreme

    init(rate: Double) {
        switch rate {
        case ..<0.5: self = .quiet
        case ..<1.0: self = .low
        case ..<3.0: self = .normal
        case ..<7.0: self = .active
        case ..<15.0: self = .high
        default: self = .extreme
        }
    }

    var displayName: String {
        switch self {
        case .quiet: return "清淡"
        case .low: return "偏低"
        case .normal: return "正常"
        case .active: return "活跃"
        case .high: return "高换手"
        case .extreme: return "极端"
        }
    }
}

enum VolumeRatioLevel: Equatable {
    case quiet
    case low
    case normal
    case active
    case high
    case extreme

    init(ratio: Double) {
        switch ratio {
        case ..<0.5: self = .quiet
        case ..<0.8: self = .low
        case ..<1.5: self = .normal
        case ..<2.5: self = .active
        case ..<5.0: self = .high
        default: self = .extreme
        }
    }

    var displayName: String {
        switch self {
        case .quiet: return "清淡"
        case .low: return "偏低"
        case .normal: return "正常"
        case .active: return "活跃"
        case .high: return "放量"
        case .extreme: return "极端"
        }
    }
}

struct SectorSnapshot: Equatable {
    let name: String
    let changePercent: Double

    var formattedPercent: String {
        let sign = changePercent >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", changePercent)
    }
}

final class FundFlowService {

    static func fetchAStockFundFlow(stock: Stock) async throws -> FundFlowSnapshot? {
        guard stock.market == .aStock,
              let secid = eastmoneySecid(for: stock.id) else { return nil }

        let fields = "f1,f2,f3,f7,f8,f10,f12,f13,f14,f62,f64,f65,f66,f69,f70,f71,f72,f75,f76,f77,f78,f81,f82,f83,f84,f87,f100,f124"
        let urlString = "https://push2delay.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=\(secid)&fields=\(fields)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let parsed = parseEastmoneyFundFlow(data) else {
            throw URLError(.cannotParseResponse)
        }
        return FundFlowSnapshot(
            mainNetInflow: parsed.mainNetInflow,
            orderFlows: parsed.orderFlows,
            turnoverRate: parsed.turnoverRate,
            volumeRatio: parsed.volumeRatio,
            amplitude: parsed.amplitude,
            updateTime: parsed.updateTime,
            primarySectorName: parsed.primarySectorName
        )
    }

    static func fetchAStockFundFlowTrend(stock: Stock) async throws -> [FundFlowMinutePoint]? {
        guard stock.market == .aStock,
              let secid = eastmoneySecid(for: stock.id) else { return nil }

        let fields1 = "f1,f2,f3,f7"
        let fields2 = "f51,f52,f53,f54,f55,f56"
        let urlString = "https://push2.eastmoney.com/api/qt/stock/fflow/kline/get?lmt=0&klt=1&fields1=\(fields1)&fields2=\(fields2)&secid=\(secid)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://data.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let points = parseEastmoneyFundFlowTrend(data) else {
            throw URLError(.cannotParseResponse)
        }
        return points
    }

    static func fetchAStockSectors(stock: Stock) async throws -> [SectorSnapshot]? {
        guard stock.market == .aStock,
              let secid = eastmoneySecid(for: stock.id) else { return nil }

        let fields = "f12,f14,f3,f128"
        let urlString = "https://push2delay.eastmoney.com/api/qt/slist/get?fltt=2&invt=2&secid=\(secid)&spt=3&pi=0&pz=200&po=1&fields=\(fields)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let snapshots = parseEastmoneySectors(data) else {
            throw URLError(.cannotParseResponse)
        }
        return snapshots
    }

    static func parseEastmoneyFundFlow(_ data: Data) -> (
        mainNetInflow: Double,
        turnoverRate: Double?,
        volumeRatio: Double?,
        amplitude: Double?,
        updateTime: String,
        primarySectorName: String?,
        orderFlows: [FundFlowOrderSnapshot]
    )? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let diff = dataObj["diff"] as? [[String: Any]],
              let item = diff.first,
              let mainNetInflow = numericValue(item["f62"]) else { return nil }

        let primarySectorName = (item["f100"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (
            mainNetInflow,
            numericValue(item["f8"]),
            numericValue(item["f10"]),
            numericValue(item["f7"]),
            formatEastmoneyTimestamp(item["f124"]),
            primarySectorName,
            [
                FundFlowOrderSnapshot(
                    size: .superLarge,
                    inflow: numericValue(item["f64"]),
                    outflow: numericValue(item["f65"]),
                    netInflow: numericValue(item["f66"]),
                    netRatio: numericValue(item["f69"])
                ),
                FundFlowOrderSnapshot(
                    size: .large,
                    inflow: numericValue(item["f70"]),
                    outflow: numericValue(item["f71"]),
                    netInflow: numericValue(item["f72"]),
                    netRatio: numericValue(item["f75"])
                ),
                FundFlowOrderSnapshot(
                    size: .medium,
                    inflow: numericValue(item["f76"]),
                    outflow: numericValue(item["f77"]),
                    netInflow: numericValue(item["f78"]),
                    netRatio: numericValue(item["f81"])
                ),
                FundFlowOrderSnapshot(
                    size: .small,
                    inflow: numericValue(item["f82"]),
                    outflow: numericValue(item["f83"]),
                    netInflow: numericValue(item["f84"]),
                    netRatio: numericValue(item["f87"])
                ),
            ]
        )
    }

    static func parseEastmoneyFundFlowTrend(_ data: Data) -> [FundFlowMinutePoint]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let klines = dataObj["klines"] as? [String] else { return nil }

        let points = klines.compactMap { line -> FundFlowMinutePoint? in
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
            guard values.count >= 6,
                  let mainNetInflow = Double(values[1]),
                  let smallNetInflow = Double(values[2]),
                  let mediumNetInflow = Double(values[3]),
                  let largeNetInflow = Double(values[4]),
                  let superLargeNetInflow = Double(values[5]) else { return nil }

            return FundFlowMinutePoint(
                time: String(values[0]),
                mainNetInflow: mainNetInflow,
                smallNetInflow: smallNetInflow,
                mediumNetInflow: mediumNetInflow,
                largeNetInflow: largeNetInflow,
                superLargeNetInflow: superLargeNetInflow
            )
        }

        return points.isEmpty ? nil : points
    }

    static func aggregateMainFundFlowByThirtyMinutes(
        _ points: [FundFlowMinutePoint]
    ) -> [FundFlowPeriodSnapshot] {
        let periods: [(start: Int, end: Int, startLabel: String, endLabel: String)] = [
            (570, 600, "09:30", "10:00"),
            (600, 630, "10:00", "10:30"),
            (630, 660, "10:30", "11:00"),
            (660, 690, "11:00", "11:30"),
            (780, 810, "13:00", "13:30"),
            (810, 840, "13:30", "14:00"),
            (840, 870, "14:00", "14:30"),
            (870, 900, "14:30", "15:00"),
        ]
        let samples = points.compactMap { point -> (minute: Int, amount: Double)? in
            guard let minute = minuteOfDay(point.time) else { return nil }
            return (minute, point.mainNetInflow)
        }.sorted { $0.minute < $1.minute }

        return periods.compactMap { period in
            guard let endSample = samples.last(where: {
                $0.minute > period.start && $0.minute <= period.end
            }) else { return nil }

            let baseline: Double
            if period.start == periods[0].start {
                baseline = 0
            } else {
                guard let startSample = samples.last(where: { $0.minute <= period.start }) else {
                    return nil
                }
                baseline = startSample.amount
            }

            return FundFlowPeriodSnapshot(
                startTime: period.startLabel,
                endTime: period.endLabel,
                netInflow: endSample.amount - baseline
            )
        }
    }

    static func parseEastmoneySector(_ data: Data) -> SectorSnapshot? {
        parseEastmoneySectors(data)?.first
    }

    static func parseEastmoneySectors(_ data: Data) -> [SectorSnapshot]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let items = sectorItems(from: dataObj["diff"]) else { return nil }

        let snapshots = items.compactMap { item -> SectorSnapshot? in
            guard let name = item["f14"] as? String,
                  !name.isEmpty,
                  let changePercent = numericValue(item["f3"]) else { return nil }
            return SectorSnapshot(name: name, changePercent: changePercent)
        }

        return snapshots.isEmpty ? nil : snapshots
    }

    static func primarySector(
        from sectors: [SectorSnapshot],
        matching primarySectorName: String?
    ) -> SectorSnapshot? {
        guard let primarySectorName,
              let matched = sectors.first(where: { $0.name == primarySectorName }) else {
            return sectors.first
        }
        return matched
    }

    static func eastmoneySecid(for stockId: String) -> String? {
        let id = stockId.lowercased()
        if id.hasPrefix("sh") {
            return "1.\(String(id.dropFirst(2)))"
        }
        if id.hasPrefix("sz") || id.hasPrefix("bj") {
            return "0.\(String(id.dropFirst(2)))"
        }
        return nil
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func minuteOfDay(_ value: String) -> Int? {
        guard let time = value.split(separator: " ").last else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    private static func sectorItems(from value: Any?) -> [[String: Any]]? {
        if let items = value as? [[String: Any]] {
            return items
        }
        guard let items = value as? [String: Any] else { return nil }

        let sortedKeys = items.keys.sorted { lhs, rhs in
            if let left = Int(lhs), let right = Int(rhs) {
                return left < right
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return sortedKeys.compactMap { items[$0] as? [String: Any] }
    }

    private static func formatEastmoneyTimestamp(_ value: Any?) -> String {
        guard let timestamp = numericValue(value), timestamp > 0 else { return "" }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
