import XCTest
@testable import Stockbar

final class KoreanMarketSessionTests: XCTestCase {

    private func kstDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func test_session_at_open() {
        // 2026-05-14 (Thursday) 09:00 KST → 盘中
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 9, minute: 0)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_one_minute_after_open() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 9, minute: 1)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_one_minute_before_close() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 15, minute: 29)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_at_close_inclusive() {
        // 15:30 inclusive — last point of trading
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 15, minute: 30)
        XCTAssertEqual(AppState.koreanMarketSession(at: d), "盘中")
    }

    func test_session_one_minute_after_close() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 15, minute: 31)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }

    func test_session_before_open() {
        let d = kstDate(year: 2026, month: 5, day: 14, hour: 8, minute: 59)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }

    func test_session_saturday_returns_nil() {
        // 2026-05-16 is Saturday
        let d = kstDate(year: 2026, month: 5, day: 16, hour: 10, minute: 0)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }

    func test_session_sunday_returns_nil() {
        // 2026-05-17 is Sunday
        let d = kstDate(year: 2026, month: 5, day: 17, hour: 10, minute: 0)
        XCTAssertNil(AppState.koreanMarketSession(at: d))
    }
}
