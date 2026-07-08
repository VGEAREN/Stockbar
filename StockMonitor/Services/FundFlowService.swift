import Foundation

struct FundFlowSnapshot {
    let mainNetInflow: Double
    let updateTime: String
}

final class FundFlowService {

    static func fetchAStockFundFlow(stock: Stock) async throws -> FundFlowSnapshot? {
        guard stock.market == .aStock,
              let secid = eastmoneySecid(for: stock.id) else { return nil }

        let fields = "f1,f2,f3,f12,f13,f14,f62,f66,f69,f72,f75,f78,f81,f84,f87,f124"
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
            updateTime: parsed.updateTime
        )
    }

    static func parseEastmoneyFundFlow(_ data: Data) -> (mainNetInflow: Double, updateTime: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let diff = dataObj["diff"] as? [[String: Any]],
              let item = diff.first,
              let mainNetInflow = numericValue(item["f62"]) else { return nil }

        return (mainNetInflow, formatEastmoneyTimestamp(item["f124"]))
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

    private static func formatEastmoneyTimestamp(_ value: Any?) -> String {
        guard let timestamp = numericValue(value), timestamp > 0 else { return "" }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
