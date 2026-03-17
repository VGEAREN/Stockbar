import XCTest
@testable import StockMonitor

final class StockTests: XCTestCase {

    func test_market_fromCode_aStock() {
        XCTAssertEqual(Market.from(code: "sh600000"), .aStock)
        XCTAssertEqual(Market.from(code: "sz000001"), .aStock)
        XCTAssertEqual(Market.from(code: "bj430047"), .aStock)
    }

    func test_market_fromCode_usStock() {
        XCTAssertEqual(Market.from(code: "usr_aapl"), .usStock)
        XCTAssertEqual(Market.from(code: "usr_nvda"), .usStock)
    }

    func test_market_fromCode_hkStock() {
        XCTAssertEqual(Market.from(code: "hk00700"), .hkStock)
        XCTAssertEqual(Market.from(code: "hk03690"), .hkStock)
    }

    func test_stock_codable_roundtrip() throws {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock,
                         costPrice: 8.5, holdingShares: 1000)
        let data = try JSONEncoder().encode(stock)
        let decoded = try JSONDecoder().decode(Stock.self, from: data)
        XCTAssertEqual(decoded.id, "sh600000")
        XCTAssertEqual(decoded.name, "浦发银行")
        XCTAssertEqual(decoded.market, .aStock)
        XCTAssertEqual(decoded.costPrice, 8.5)
        XCTAssertEqual(decoded.holdingShares, 1000)
    }

    func test_pnl_withHolding() {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock,
                         costPrice: 8.0, holdingShares: 1000)
        let quote = Quote(code: "sh600000", price: 9.0, change: 1.0,
                         changePercent: 12.5, updateTime: "15:00:00")
        XCTAssertEqual(stock.pnl(quote: quote)!, 1000.0, accuracy: 0.001)
    }

    func test_pnl_withoutHolding_returnsNil() {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock,
                         costPrice: nil, holdingShares: nil)
        let quote = Quote(code: "sh600000", price: 9.0, change: 1.0,
                         changePercent: 12.5, updateTime: "15:00:00")
        XCTAssertNil(stock.pnl(quote: quote))
    }

    func test_pnl_negative() {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock,
                         costPrice: 10.0, holdingShares: 500)
        let quote = Quote(code: "sh600000", price: 9.0, change: -1.0,
                         changePercent: -10.0, updateTime: "15:00:00")
        XCTAssertEqual(stock.pnl(quote: quote)!, -500.0, accuracy: 0.001)
    }
}
