import XCTest
@testable import Stockbar

/// 夜盘（Blue Ocean ATS）只在周日~周四 ET 20:00–次日 04:00 交易，周五晚没有夜盘
final class USMarketSessionTests: XCTestCase {

    private func etDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_fridayEvening_isNotOvernight() {
        // 2026-10-09 (Friday) 21:00 ET
        let d = etDate(year: 2026, month: 10, day: 9, hour: 21, minute: 0)
        XCTAssertNil(AppState.usMarketSession(at: d))
    }

    func test_saturdayEarlyMorning_isNotOvernight() {
        // 2026-10-10 (Saturday) 02:00 ET
        let d = etDate(year: 2026, month: 10, day: 10, hour: 2, minute: 0)
        XCTAssertNil(AppState.usMarketSession(at: d))
    }

    func test_thursdayEvening_isOvernight() {
        // 2026-10-08 (Thursday) 21:00 ET — 本周最后一个夜盘
        let d = etDate(year: 2026, month: 10, day: 8, hour: 21, minute: 0)
        XCTAssertEqual(AppState.usMarketSession(at: d), "夜盘")
    }

    func test_fridayEarlyMorning_isOvernight() {
        // 2026-10-09 (Friday) 02:00 ET — 周四晚夜盘的延续
        let d = etDate(year: 2026, month: 10, day: 9, hour: 2, minute: 0)
        XCTAssertEqual(AppState.usMarketSession(at: d), "夜盘")
    }

    func test_sundayEvening_atOpen_isOvernight() {
        // 2026-10-11 (Sunday) 20:00 ET — 新一周夜盘开盘
        let d = etDate(year: 2026, month: 10, day: 11, hour: 20, minute: 0)
        XCTAssertEqual(AppState.usMarketSession(at: d), "夜盘")
    }

    // MARK: - 盘外价的时段名（休市时新浪给的是上一个交易日的盘后收盘价）

    func test_extendedPriceLabel_closedMarket_isAfterHours() {
        // 2026-11-20 (Friday) 22:45 ET = 北京周六 11:45，周五晚没有夜盘
        XCTAssertEqual(AppState.usExtendedPriceLabel(at: etDate(year: 2026, month: 11, day: 20, hour: 22, minute: 45)), "盘后")
        // 周六中午
        XCTAssertEqual(AppState.usExtendedPriceLabel(at: etDate(year: 2026, month: 11, day: 21, hour: 12, minute: 0)), "盘后")
        // 周日 19:59，夜盘开盘前一分钟
        XCTAssertEqual(AppState.usExtendedPriceLabel(at: etDate(year: 2026, month: 11, day: 22, hour: 19, minute: 59)), "盘后")
    }

    func test_extendedPriceLabel_tradingDay_followsSession() {
        XCTAssertEqual(AppState.usExtendedPriceLabel(at: etDate(year: 2026, month: 11, day: 19, hour: 5, minute: 0)), "盘前")
        XCTAssertEqual(AppState.usExtendedPriceLabel(at: etDate(year: 2026, month: 11, day: 19, hour: 17, minute: 0)), "盘后")
        XCTAssertEqual(AppState.usExtendedPriceLabel(at: etDate(year: 2026, month: 11, day: 22, hour: 20, minute: 0)), "夜盘")
    }
}
