import Foundation

enum ColorTheme: String, Codable, CaseIterable {
    case chinese = "chinese"  // 红涨绿跌
    case western = "western"  // 绿涨红跌

    var displayName: String {
        switch self {
        case .chinese: return "红涨绿跌"
        case .western: return "绿涨红跌"
        }
    }
}

struct AppSettings {
    var colorScheme: ColorTheme
    var refreshInterval: Int        // 秒，合法值见 validRefreshIntervals
    var statusBarStockId: String?

    static let validRefreshIntervals = [3, 5, 10, 30]

    /// 上涨颜色 Asset 名称（在 Assets.xcassets 中定义）
    var upColorName: String   { colorScheme == .chinese ? "upRed"   : "upGreen" }
    /// 下跌颜色 Asset 名称
    var downColorName: String { colorScheme == .chinese ? "downGreen" : "downRed" }
}
