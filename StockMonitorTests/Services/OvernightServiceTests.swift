import XCTest
@testable import Stockbar

final class OvernightServiceTests: XCTestCase {

    // 夹具抓取于 2026-10-08 23:58 EDT（夜盘中），该晚夜盘 20:00 EDT 开盘 = 2026-10-09T00:00:00Z
    private let sessionStart = OvernightServiceTests.date("2026-10-09T00:00:00Z")
    private let codes = ["usr_aapl", "usr_tsla", "usr_brk.b", "usr_tcehy", "usr_zzzzzq"]

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"),
                                "Fixture \(name).json missing")
        return try Data(contentsOf: url)
    }

    // MARK: - parseOvernightPrices

    func test_parse_keepsOnlyTradesSinceSessionStart_keyedByStockCode() throws {
        // AAPL/TSLA (boats) 与 BRK.B (bruce, 纳秒时间戳) 为夜盘成交；
        // TCEHY 不支持夜盘，最后盘外成交在 16:00 EDT，应丢弃；ZZZZZQ 不存在（results 中为 null）
        let data = try loadFixture("robinhood_quotes_overnight")
        let prices = OvernightService.parseOvernightPrices(data, codes: codes, sessionStart: sessionStart)
        XCTAssertEqual(prices, ["usr_aapl": 340.43, "usr_tsla": 377.26, "usr_brk.b": 511.24])
    }

    func test_parse_tradeExactlyAtSessionStart_isKept() throws {
        // TCEHY 最后盘外成交时间恰为 2026-10-08T20:00:00Z（无小数秒）
        let data = try loadFixture("robinhood_quotes_overnight")
        let prices = OvernightService.parseOvernightPrices(
            data, codes: ["usr_tcehy"], sessionStart: Self.date("2026-10-08T20:00:00Z"))
        XCTAssertEqual(prices, ["usr_tcehy": 52.72])
    }

    func test_parse_tradeOneSecondBeforeSessionStart_isDropped() throws {
        let data = try loadFixture("robinhood_quotes_overnight")
        let prices = OvernightService.parseOvernightPrices(
            data, codes: ["usr_tcehy"], sessionStart: Self.date("2026-10-08T20:00:01Z"))
        XCTAssertEqual(prices, [:])
    }

    func test_parse_allSymbolsMissing_returnsEmpty() throws {
        // 全部代码都不存在时接口返回 404 + {"missing_instruments":[...]}
        let data = try loadFixture("robinhood_quotes_missing")
        XCTAssertEqual(OvernightService.parseOvernightPrices(data, codes: ["usr_zzzzzq"], sessionStart: sessionStart), [:])
    }

    func test_parse_garbageData_returnsEmpty() {
        let data = "not json".data(using: .utf8)!
        XCTAssertEqual(OvernightService.parseOvernightPrices(data, codes: codes, sessionStart: sessionStart), [:])
    }

    // MARK: - sessionStart

    func test_sessionStart_eveningET_isSameDay2000() {
        // 2026-10-08 23:58 EDT → 当晚 20:00 EDT
        XCTAssertEqual(OvernightService.sessionStart(for: Self.date("2026-10-09T03:58:00Z")),
                       Self.date("2026-10-09T00:00:00Z"))
    }

    func test_sessionStart_exactly2000ET_isThatInstant() {
        XCTAssertEqual(OvernightService.sessionStart(for: Self.date("2026-10-09T00:00:00Z")),
                       Self.date("2026-10-09T00:00:00Z"))
    }

    func test_sessionStart_afterMidnightET_isPreviousDay2000() {
        // 2026-10-09 02:30 EDT → 前一晚 20:00 EDT
        XCTAssertEqual(OvernightService.sessionStart(for: Self.date("2026-10-09T06:30:00Z")),
                       Self.date("2026-10-09T00:00:00Z"))
    }

    func test_sessionStart_winterTime_uses2000EST() {
        // 2026-12-01 21:00 EST (UTC-5) → 20:00 EST = 2026-12-02T01:00:00Z
        XCTAssertEqual(OvernightService.sessionStart(for: Self.date("2026-12-02T02:00:00Z")),
                       Self.date("2026-12-02T01:00:00Z"))
    }
}
