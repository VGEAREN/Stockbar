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
}
