import XCTest
@testable import StockMonitor

final class QuoteTests: XCTestCase {

    func test_isUp_positive() {
        let q = Quote(code: "sh600000", price: 10.0, change: 0.5,
                     changePercent: 5.0, updateTime: "10:30:00")
        XCTAssertTrue(q.isUp)
        XCTAssertFalse(q.isDown)
    }

    func test_isDown_negative() {
        let q = Quote(code: "sh600000", price: 9.0, change: -0.5,
                     changePercent: -5.0, updateTime: "10:30:00")
        XCTAssertFalse(q.isUp)
        XCTAssertTrue(q.isDown)
    }

    func test_flat() {
        let q = Quote(code: "sh600000", price: 9.5, change: 0.0,
                     changePercent: 0.0, updateTime: "10:30:00")
        XCTAssertFalse(q.isUp)
        XCTAssertFalse(q.isDown)
    }

    func test_formattedPercent_positive() {
        let q = Quote(code: "sh600000", price: 10.0, change: 0.5,
                     changePercent: 5.12, updateTime: "10:30:00")
        XCTAssertEqual(q.formattedPercent, "+5.12%")
    }

    func test_formattedPercent_negative() {
        let q = Quote(code: "sh600000", price: 9.0, change: -0.5,
                     changePercent: -3.45, updateTime: "10:30:00")
        XCTAssertEqual(q.formattedPercent, "-3.45%")
    }

    func test_formattedPercent_zero() {
        let q = Quote(code: "sh600000", price: 9.5, change: 0.0,
                     changePercent: 0.0, updateTime: "10:30:00")
        XCTAssertEqual(q.formattedPercent, "+0.00%")
    }

    func test_formattedPrice_aboveTen() {
        let q = Quote(code: "sh600519", price: 1688.0, change: 0, changePercent: 0, updateTime: "")
        XCTAssertEqual(q.formattedPrice, "1688.00")
    }

    func test_formattedPrice_belowTen() {
        let q = Quote(code: "sh600000", price: 9.56, change: 0, changePercent: 0, updateTime: "")
        XCTAssertEqual(q.formattedPrice, "9.560")
    }
}
