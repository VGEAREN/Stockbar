import Foundation

/// 美股夜盘 (ET 20:00–04:00) 实时报价
/// 数据源：Robinhood 公开行情接口（bounds=24_5，成交来自 Blue Ocean / Bruce 等夜盘 ATS），无需 API Key
final class OvernightService {

    private static let baseURL = "https://api.robinhood.com/marketdata/quotes/"

    /// 批量获取美股夜盘价格，返回 [stockCode: overnightPrice]
    /// stockCodes 格式如 ["usr_aapl", "usr_tsla"]，一次请求取回全部
    static func fetchOvernightPrices(codes: [String]) async -> [String: Double] {
        guard !codes.isEmpty else { return [:] }
        var comps = URLComponents(string: baseURL)
        comps?.queryItems = [
            URLQueryItem(name: "symbols", value: codes.map(symbol(for:)).joined(separator: ",")),
            URLQueryItem(name: "bounds", value: "24_5"),
        ]
        guard let url = comps?.url else { return [:] }
        // 与 A股/港股 刷新并行等待，超时要短，避免拖住其他市场的行情更新
        let req = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [:] }
        return parseOvernightPrices(data, codes: codes, sessionStart: sessionStart(for: Date()))
    }

    /// 解析行情响应（抽出供单元测试使用）
    /// 不支持夜盘的股票返回的是盘后/正盘的旧成交，只保留本次夜盘开盘后的成交价
    static func parseOvernightPrices(_ data: Data, codes: [String], sessionStart: Date) -> [String: Double] {
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [Any] else { return [:] }
        let codeBySymbol = Dictionary(codes.map { (symbol(for: $0), $0) }, uniquingKeysWith: { a, _ in a })
        var prices: [String: Double] = [:]
        // 不存在的代码在 results 中为 null，由 case let 过滤
        for case let item as [String: Any] in results {
            guard let symbol = item["symbol"] as? String,
                  let code   = codeBySymbol[symbol],
                  let price  = (item["last_non_reg_trade_price"] as? String).flatMap(Double.init),
                  price > 0,
                  let time   = (item["venue_last_non_reg_trade_time"] as? String).flatMap(parseTime),
                  time >= sessionStart else { continue }
            prices[code] = price
        }
        return prices
    }

    /// 本次夜盘的开盘时间：不晚于 now 的最近一个美东 20:00
    static func sessionStart(for now: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        guard let today = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) else { return now }
        return today <= now ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
    }

    // usr_brk.b → BRK.B
    private static func symbol(for code: String) -> String {
        code.replacingOccurrences(of: "usr_", with: "").uppercased()
    }

    // 小数秒位数不固定（毫秒 / 纳秒 / 无），去掉后按秒解析
    private static func parseTime(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
