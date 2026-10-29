import XCTest
@testable import Stockbar

@MainActor
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

    func test_market_fromCode_krStock_kospi() {
        XCTAssertEqual(Market.from(code: "kr_005930.ks"), .krStock)
    }

    func test_market_fromCode_krStock_kosdaq() {
        XCTAssertEqual(Market.from(code: "kr_293490.kq"), .krStock)
    }

    func test_market_krStock_rawValue() {
        XCTAssertEqual(Market.krStock.rawValue, "韩股")
    }

    func test_market_allCases_includes_kr() {
        XCTAssertTrue(Market.allCases.contains(.krStock))
    }

    func test_stock_codable_roundtrip_kr() throws {
        let stock = Stock(id: "kr_005930.ks", name: "Samsung Electronics", market: .krStock,
                         costPrice: 80000.0, holdingShares: 10)
        let data = try JSONEncoder().encode(stock)
        let decoded = try JSONDecoder().decode(Stock.self, from: data)
        XCTAssertEqual(decoded.id, "kr_005930.ks")
        XCTAssertEqual(decoded.market, .krStock)
        XCTAssertEqual(decoded.costPrice, 80000.0)
    }

    // MARK: - 到价提醒持久化

    func test_stock_decodesLegacyJSONWithoutAlert() throws {
        let json = #"{"id":"sh600000","name":"浦发银行","market":"A股","costPrice":8.5,"holdingShares":1000}"#
        let s = try JSONDecoder().decode(Stock.self, from: Data(json.utf8))
        XCTAssertNil(s.alert)
        XCTAssertEqual(s.costPrice, 8.5)
    }

    func test_stock_codable_roundtrip_withAlert() throws {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock, costPrice: nil, holdingShares: nil,
                          alert: PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))
        let decoded = try JSONDecoder().decode(Stock.self, from: JSONEncoder().encode(stock))
        XCTAssertEqual(decoded, stock)
    }

    func test_stock_corruptAlert_keepsOtherFields() throws {
        let json = #"{"id":"sh600000","name":"浦发银行","market":"A股","holdingShares":1000,"alert":{"targetPrice":"oops"}}"#
        let s = try JSONDecoder().decode(Stock.self, from: Data(json.utf8))
        XCTAssertNil(s.alert)
        XCTAssertEqual(s.holdingShares, 1000)
    }

    func test_stockList_oneCorruptAlert_doesNotEmptyTheList() throws {
        let json = #"[{"id":"sh600000","name":"A","market":"A股","alert":{"targetPrice":"oops"}},{"id":"hk00700","name":"B","market":"港股"}]"#
        let list = try JSONDecoder().decode([Stock].self, from: Data(json.utf8))
        XCTAssertEqual(list.map(\.id), ["sh600000", "hk00700"])
    }

    func test_stock_withoutAlert_doesNotWriteAlertKey() throws {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock, costPrice: nil, holdingShares: nil)
        let json = String(decoding: try JSONEncoder().encode(stock), as: UTF8.self)
        XCTAssertFalse(json.contains("alert"))
    }
}
