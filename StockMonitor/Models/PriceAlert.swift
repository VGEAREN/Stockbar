import Foundation

/// 到价提醒：每只股票一个目标价。方向（涨到 / 跌到）在布防时按当时价格自动判断，
/// 到价后只通知一次并自动关闭开关
struct PriceAlert: Codable, Equatable {
    enum Direction: String, Codable {
        case rise   // 涨到
        case fall   // 跌到
    }

    var targetPrice: Double
    var direction: Direction?   // nil = 布防时还没有可用价格，首次拿到价格时再定
    var isEnabled: Bool         // 这只股票的提醒开关

    /// 目标价 ≥ 现价 → 等涨到；否则 → 等跌到
    static func direction(target: Double, currentPrice: Double) -> Direction {
        target >= currentPrice ? .rise : .fall
    }

    /// 是否到价：开关开启、方向已定、价格有效时，涨到 = 价格 ≥ 目标价，跌到 = 价格 ≤ 目标价
    func isReached(by price: Double) -> Bool {
        guard isEnabled, price > 0, let direction else { return false }
        switch direction {
        case .rise: return price >= targetPrice
        case .fall: return price <= targetPrice
        }
    }

    /// 解析编辑页输入的目标价：去掉首尾空白后必须是有限正数，否则返回 nil
    static func parseTarget(_ text: String) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// 编辑页保存时生成新的提醒。
    /// - 重新布防（新建并开启 / 开关从关到开 / 开启状态下改了目标价）→ 用当前价格重新定方向；没有价格先留空
    /// - 其它情况（开关一直开着、目标价没变）→ 保持原方向，避免价格已越过目标价时把方向弄反
    static func edited(previous: PriceAlert?, targetPrice: Double, isEnabled: Bool,
                       currentPrice: Double?) -> PriceAlert {
        let staysArmed = previous?.isEnabled == true && previous?.targetPrice == targetPrice
        let direction: Direction?
        if isEnabled && !staysArmed {
            direction = currentPrice.flatMap { $0 > 0 ? Self.direction(target: targetPrice, currentPrice: $0) : nil }
        } else {
            direction = previous?.direction
        }
        return PriceAlert(targetPrice: targetPrice, direction: direction, isEnabled: isEnabled)
    }

    /// 界面上的简短描述："涨到 11.00" / "跌到 9.500"；方向未定时 "目标 9.500"
    var summary: String {
        let target = Quote.format(targetPrice)
        switch direction {
        case .rise?: return "涨到 \(target)"
        case .fall?: return "跌到 \(target)"
        case nil:    return "目标 \(target)"
        }
    }

    /// 主列表角标："↑11.00" / "↓9.500"；方向未定时只显示目标价
    var badge: String {
        let target = Quote.format(targetPrice)
        switch direction {
        case .rise?: return "↑\(target)"
        case .fall?: return "↓\(target)"
        case nil:    return target
        }
    }
}

/// 一次到价：拼通知文案所需的全部信息
struct PriceAlertHit: Equatable {
    let stockId: String
    let stockName: String
    let price: Double
    let targetPrice: Double
    let direction: PriceAlert.Direction
    let sessionLabel: String?   // 美股用时段价时为 "盘前" / "盘后" / "夜盘"

    var title: String { "\(stockName) 到价提醒" }

    var body: String {
        let verb = direction == .rise ? "涨到" : "跌到"
        return "\(sessionLabel ?? "现价") \(Quote.format(price))，已\(verb)目标价 \(Quote.format(targetPrice))"
    }
}
