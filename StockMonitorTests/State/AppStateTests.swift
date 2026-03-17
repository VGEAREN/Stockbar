import XCTest
@testable import StockMonitor

@MainActor
final class AppStateTests: XCTestCase {
    var sut: AppState!

    override func setUp() {
        super.setUp()
        sut = AppState()
        sut.stocks = []
        sut.quotes = [:]
        sut.statusBarStockId = ""
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func test_statusBarStock_returnsNilWhenEmpty() {
        sut.stocks = []
        XCTAssertNil(sut.statusBarStock)
    }

    func test_statusBarStock_fallbackToFirstWhenIdNotFound() {
        let s = Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil)
        sut.stocks = [s]
        sut.statusBarStockId = "nonexistent"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600000")
    }

    func test_statusBarStock_matchesById() {
        let s1 = Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil)
        let s2 = Stock(id: "sh600001", name: "股票2", market: .aStock, costPrice: nil, holdingShares: nil)
        sut.stocks = [s1, s2]
        sut.statusBarStockId = "sh600001"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600001")
    }

    func test_hasPnLData_falseWithNoHoldings() {
        sut.stocks = [Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil)]
        XCTAssertFalse(sut.hasPnLData)
    }

    func test_hasPnLData_trueWithHolding() {
        sut.stocks = [Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: 10.0, holdingShares: 100)]
        XCTAssertTrue(sut.hasPnLData)
    }

    func test_totalPnL_sumsPnLsFromQuotes() {
        sut.stocks = [
            Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: 10.0, holdingShares: 100),
            Stock(id: "sh600001", name: "股票2", market: .aStock, costPrice: 5.0,  holdingShares: 200)
        ]
        sut.quotes = [
            "sh600000": Quote(code: "sh600000", price: 12.0, change: 2.0,  changePercent: 20.0,  updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 4.0,  change: -1.0, changePercent: -20.0, updateTime: "")
        ]
        // (12-10)*100 + (4-5)*200 = 200 - 200 = 0
        XCTAssertEqual(sut.totalPnL, 0.0, accuracy: 0.001)
    }

    func test_totalPnL_skipsStocksWithoutQuotes() {
        sut.stocks = [Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: 10.0, holdingShares: 100)]
        sut.quotes = [:]
        XCTAssertEqual(sut.totalPnL, 0.0, accuracy: 0.001)
    }
}
