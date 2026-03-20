import Foundation

/// 美股夜盘 (ET 20:00–04:00) 实时报价
/// 数据源：Pyth Network / TradingView BOATS（via Vercel API）
final class PythService {

    private static let baseURL = "https://us-overnight-stock-api.vercel.app/api"

    /// 批量获取美股夜盘价格，返回 [stockCode: overnightPrice]
    /// stockCodes 格式如 ["usr_aapl", "usr_tsla"]
    static func fetchOvernightPrices(codes: [String]) async -> [String: Double] {
        var result: [String: Double] = [:]

        await withTaskGroup(of: (String, Double?).self) { group in
            for code in codes {
                group.addTask {
                    let symbol = code.replacingOccurrences(of: "usr_", with: "").uppercased()
                    let price = await fetchPrice(symbol: symbol)
                    return (code, price)
                }
            }
            for await (code, price) in group {
                if let p = price {
                    result[code] = p
                }
            }
        }
        return result
    }

    /// 获取单只股票夜盘价格
    private static func fetchPrice(symbol: String) async -> Double? {
        guard let url = URL(string: "\(baseURL)?symbol=\(symbol)&session=overnight") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let price = json["price"] as? Double,
              price > 0 else { return nil }
        return price
    }
}
