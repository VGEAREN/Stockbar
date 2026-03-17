import XCTest
@testable import StockMonitor

final class RefreshSchedulerTests: XCTestCase {

    private func makeDate(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        c.weekday = weekday
        c.hour    = hour
        c.minute  = minute
        c.second  = 0
        return cal.date(from: c) ?? Date()
    }

    // A股上午开盘
    func test_aStock_morningSession_isTrading() {
        let d = makeDate(weekday: 2, hour: 10, minute: 0)  // 周一 10:00
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // A股下午开盘
    func test_aStock_afternoonSession_isTrading() {
        let d = makeDate(weekday: 2, hour: 14, minute: 0)  // 周一 14:00
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // 午休不交易
    func test_aStock_lunchBreak_notTrading() {
        let d = makeDate(weekday: 2, hour: 12, minute: 0)  // 周一 12:00
        // 12:00 不在 A股/港股开市段，美股也未开盘 → false
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
    }

    // 周末不交易
    func test_weekend_notTrading() {
        let d = makeDate(weekday: 1, hour: 10, minute: 0)  // 周日 10:00
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
        let d2 = makeDate(weekday: 7, hour: 10, minute: 0) // 周六 10:00
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d2))
    }

    // 美股晚间开盘
    func test_usStock_evening_isTrading() {
        let d = makeDate(weekday: 2, hour: 22, minute: 0)  // 周一 22:00（美股盘中）
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // 美股凌晨跨日
    func test_usStock_earlyMorning_isTrading() {
        let d = makeDate(weekday: 3, hour: 3, minute: 0)   // 周二 03:00（美股尾盘）
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // 非交易时间（下午收市后、美股未开盘前）
    func test_afterClose_notTrading() {
        let d = makeDate(weekday: 2, hour: 16, minute: 30) // 周一 16:30
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
    }
}
