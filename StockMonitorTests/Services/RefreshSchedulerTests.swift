import XCTest
@testable import Stockbar

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

    // A股午休时段：北京 12:00 是美股夜盘时段（KR市/夜盘覆盖），所以仍刷新
    // 自 v1.1.7 起 isTradingHour 在工作日内全天返回 true（美股四时段 + 夜盘覆盖 24h）
    func test_aStock_lunchBreak_isTrading_dueToUSOvernight() {
        let d = makeDate(weekday: 2, hour: 12, minute: 0)  // 周一 12:00
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
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

    // A股收市后：北京 16:30 是美股盘前时段，仍刷新
    func test_afterClose_isTrading_dueToUSPreMarket() {
        let d = makeDate(weekday: 2, hour: 16, minute: 30) // 周一 16:30
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // MARK: - 按各市场时间判断（固定日期：2026-11 美东已是冬令时，北京比美东快 13 小时）

    private func beijing(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // 北京周六 08:30 = 美东周五 19:30 盘后：以前按"北京工作日"判断，这段不刷新
    func test_saturdayMorning_coversUSAfterHours() {
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: beijing(11, 14, 8, 30)))
    }

    // 北京周六 09:20 = 美东周五 20:20：盘后刚收 20 分钟，仍在余量内（拿收盘价）
    func test_saturdayMorning_withinCloseGrace() {
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: beijing(11, 14, 9, 20)))
    }

    // 北京周六 09:40 = 美东周五 20:40：超过 30 分钟余量
    func test_saturdayMorning_afterCloseGrace_isQuiet() {
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: beijing(11, 14, 9, 40)))
    }

    func test_weekendQuietHours() {
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: beijing(11, 14, 12, 0)))   // 周六中午
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: beijing(11, 15, 21, 30)))  // 周日晚 = 美东周日 08:30
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: beijing(11, 16, 7, 30)))   // 周一 07:30 = 首尔 08:30、美东周日 18:30
    }

    func test_mondayOpens() {
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: beijing(11, 16, 8, 0)))     // 首尔 09:00 韩股开盘
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: beijing(11, 16, 9, 0)))     // 美东周日 20:00 夜盘开盘
    }
}
