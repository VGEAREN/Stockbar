import Foundation

struct FundFlowSnapshot {
    let mainNetInflow: Double
    let updateTime: String
    let primarySectorName: String?
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

        let fields = "f1,f2,f3,f12,f13,f14,f62,f66,f69,f72,f75,f78,f81,f84,f87,f100,f124"
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
            updateTime: parsed.updateTime,
            primarySectorName: parsed.primarySectorName
        )
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

    static func parseEastmoneyFundFlow(_ data: Data) -> (mainNetInflow: Double, updateTime: String, primarySectorName: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let diff = dataObj["diff"] as? [[String: Any]],
              let item = diff.first,
              let mainNetInflow = numericValue(item["f62"]) else { return nil }

        let primarySectorName = (item["f100"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (mainNetInflow, formatEastmoneyTimestamp(item["f124"]), primarySectorName)
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
