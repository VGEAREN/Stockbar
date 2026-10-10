import Foundation

enum DisplayCurrency: String, Codable, CaseIterable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"
    case krw = "KRW"

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .hkd: return "HK$"
        case .usd: return "$"
        case .krw: return "₩"
        }
    }

    var displayName: String {
        switch self {
        case .cny: return "人民币 ¥"
        case .hkd: return "港币 HK$"
        case .usd: return "美元 $"
        case .krw: return "韩元 ₩"
        }
    }
}

enum SortRule: String, Codable, CaseIterable {
    case changeDesc = "changeDesc"
    case changeAsc  = "changeAsc"

    var displayName: String {
        switch self {
        case .changeDesc: return "涨跌幅降序"
        case .changeAsc:  return "涨跌幅升序"
        }
    }
}

enum USPriceMode: String, Codable, CaseIterable {
    case sessionPrice = "session"
    case regularPrice = "regular"

    var displayName: String {
        switch self {
        case .sessionPrice: return "当前价（时段价格）"
        case .regularPrice: return "盘中价"
        }
    }
}

enum StatusBarIconMode: String, Codable, CaseIterable {
    case appIcon = "appIcon"
    case stockInitial = "stockInitial"
    case hidden = "hidden"

    var displayName: String {
        switch self {
        case .appIcon: return "APP图标"
        case .stockInitial: return "名称首字"
        case .hidden: return "不显示"
        }
    }
}

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
    var statusBarStockId: String         = ""
    var statusBarIconMode: StatusBarIconMode = .appIcon
    var refreshInterval: Int             = 5
    var fundFlowRefreshInterval: Int     = Self.defaultFundFlowRefreshInterval
    var colorScheme: ColorTheme          = .chinese
    var displayCurrency: DisplayCurrency = .cny
    var sortRule: SortRule               = .changeDesc
    var usPriceMode: USPriceMode         = .sessionPrice
    var groupHoldings: Bool              = false
    var activeWatchlistId: String?       = nil    // nil = 真实持仓
    var doNotDisturbEnabled: Bool        = false
    var doNotDisturbStartMinutes: Int    = Self.defaultDoNotDisturbStartMinutes
    var doNotDisturbEndMinutes: Int      = Self.defaultDoNotDisturbEndMinutes
    var volatilityAlertEnabled: Bool     = false
    var volatilityAlertThreshold: Double = Self.defaultVolatilityAlertThreshold

    static let validRefreshIntervals = [3, 5, 10, 30]
    static let validFundFlowRefreshIntervals = [5, 10, 30, 60]
    static let defaultFundFlowRefreshInterval = 10
    static let defaultDoNotDisturbStartMinutes = 15 * 60
    static let defaultDoNotDisturbEndMinutes = 9 * 60 + 30
    static let defaultVolatilityAlertThreshold = 5.0
    static let volatilityAlertThresholdStep = 0.5

    var upColorName: String   { colorScheme == .chinese ? "upRed"   : "upGreen" }
    var downColorName: String { colorScheme == .chinese ? "downGreen" : "downRed" }

    static func validMinute(_ minute: Int?) -> Int? {
        guard let minute, (0..<24 * 60).contains(minute) else { return nil }
        return minute
    }

    static func validFundFlowRefreshInterval(_ interval: Int?) -> Int? {
        guard let interval, validFundFlowRefreshIntervals.contains(interval) else { return nil }
        return interval
    }

}

// MARK: - Codable（容错：缺失字段使用默认值）
extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case statusBarStockId, statusBarIconMode, refreshInterval, fundFlowRefreshInterval, colorScheme, displayCurrency, sortRule, usPriceMode, groupHoldings, activeWatchlistId
        case doNotDisturbEnabled, doNotDisturbStartMinutes, doNotDisturbEndMinutes
        case volatilityAlertEnabled, volatilityAlertThreshold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusBarStockId   = (try? c.decodeIfPresent(String.self,          forKey: .statusBarStockId))    ?? ""
        statusBarIconMode  = (try? c.decodeIfPresent(StatusBarIconMode.self, forKey: .statusBarIconMode)) ?? .appIcon
        refreshInterval    = (try? c.decodeIfPresent(Int.self,             forKey: .refreshInterval))     ?? 5
        fundFlowRefreshInterval = Self.validFundFlowRefreshInterval(try? c.decodeIfPresent(Int.self, forKey: .fundFlowRefreshInterval))
            ?? Self.defaultFundFlowRefreshInterval
        colorScheme        = (try? c.decodeIfPresent(ColorTheme.self,      forKey: .colorScheme))         ?? .chinese
        displayCurrency    = (try? c.decodeIfPresent(DisplayCurrency.self, forKey: .displayCurrency))     ?? .cny
        sortRule           = (try? c.decodeIfPresent(SortRule.self,         forKey: .sortRule))            ?? .changeDesc
        usPriceMode        = (try? c.decodeIfPresent(USPriceMode.self,     forKey: .usPriceMode))         ?? .sessionPrice
        groupHoldings      = (try? c.decodeIfPresent(Bool.self,            forKey: .groupHoldings))       ?? false
        activeWatchlistId  = try? c.decodeIfPresent(String.self,           forKey: .activeWatchlistId)
        doNotDisturbEnabled = (try? c.decodeIfPresent(Bool.self,           forKey: .doNotDisturbEnabled)) ?? false
        doNotDisturbStartMinutes = Self.validMinute(try? c.decodeIfPresent(Int.self, forKey: .doNotDisturbStartMinutes))
            ?? Self.defaultDoNotDisturbStartMinutes
        doNotDisturbEndMinutes = Self.validMinute(try? c.decodeIfPresent(Int.self, forKey: .doNotDisturbEndMinutes))
            ?? Self.defaultDoNotDisturbEndMinutes
        volatilityAlertEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .volatilityAlertEnabled)) ?? false
        volatilityAlertThreshold = (try? c.decodeIfPresent(Double.self, forKey: .volatilityAlertThreshold))
            ?? Self.defaultVolatilityAlertThreshold
    }
}
