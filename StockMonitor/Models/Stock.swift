import Foundation

enum Market: String, Codable, CaseIterable {
    case aStock  = "A股"
    case hkStock = "港股"
    case usStock = "美股"

    static func from(code: String) -> Market {
        if code.hasPrefix("hk")   { return .hkStock }
        if code.hasPrefix("usr_") { return .usStock }
        return .aStock
    }
}

struct Stock: Identifiable, Codable, Equatable {
    var id: String              // 股票代码，如 "sh600000"、"usr_aapl"、"hk00700"
    var name: String
    var market: Market
    var costPrice: Double?      // 持仓成本价（nil = 未设置）
    var holdingShares: Double?  // 持仓股数（nil = 未设置）

    /// 持仓浮盈亏 = (当前价 - 成本价) × 股数；未设置持仓则返回 nil
    func pnl(quote: Quote) -> Double? {
        guard let cost = costPrice, let shares = holdingShares else { return nil }
        return (quote.price - cost) * shares
    }

    /// 当日盈亏 = 涨跌额 × 股数；未设置股数则返回 nil
    func dailyPnl(quote: Quote) -> Double? {
        guard let shares = holdingShares else { return nil }
        return quote.change * shares
    }
}
