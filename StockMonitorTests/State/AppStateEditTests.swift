import XCTest
@testable import Stockbar

/// 编辑页「保存」：成本 / 股数写观察仓或真实持仓，提醒始终写在股票本身
@MainActor
final class AppStateEditTests: XCTestCase {
    var sut: AppState!
    var tmpDir: URL!

    override func setUp() {
        super.setUp()
        // 隔离真实数据目录（同 AppStateTests）
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StockbarTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        AppState.appSupportDirOverride = tmpDir
        sut = AppState()
        sut.stocks = []
        sut.quotes = [:]
    }

    override func tearDown() {
        sut = nil
        AppState.appSupportDirOverride = nil
        if let d = tmpDir { try? FileManager.default.removeItem(at: d) }
        tmpDir = nil
        super.tearDown()
    }

    private func date(_ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 29   // 周四
        c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeStock(alert: PriceAlert? = nil) -> Stock {
        Stock(id: "sh600000", name: "浦发银行", market: .aStock, costPrice: nil, holdingShares: nil, alert: alert)
    }

    private func setPrice(_ p: Double) {
        sut.quotes = ["sh600000": Quote(code: "sh600000", price: p, change: 0, changePercent: 0, updateTime: "")]
    }

    func test_saveEdit_realHoldings_writesHoldingAndAlertTogether() {
        sut.stocks = [makeStock()]
        setPrice(10)

        let saved = sut.saveEdit(stockId: "sh600000", cost: 8.5, shares: 1000,
                                 alertTargetText: "9.5", alertEnabled: true, now: date(10, 0))

        XCTAssertEqual(saved, PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))
        XCTAssertEqual(sut.stocks[0].costPrice, 8.5)
        XCTAssertEqual(sut.stocks[0].holdingShares, 1000)
        XCTAssertEqual(sut.stocks[0].alert, saved)
    }

    func test_saveEdit_watchlist_holdingToWatchlist_alertStaysOnStock() {
        sut.stocks = [makeStock()]
        sut.watchlists = [Watchlist(id: "wl1", name: "观察仓")]
        sut.config.activeWatchlistId = "wl1"
        setPrice(10)

        sut.saveEdit(stockId: "sh600000", cost: 8.5, shares: 1000,
                     alertTargetText: "9.5", alertEnabled: true, now: date(10, 0))

        XCTAssertEqual(sut.watchlists[0].entries["sh600000"]?.costPrice, 8.5)
        XCTAssertNil(sut.stocks[0].costPrice, "观察仓模式不改真实持仓")
        XCTAssertEqual(sut.stocks[0].alert?.targetPrice, 9.5)
    }

    func test_saveEdit_invalidTarget_removesAlert() {
        sut.stocks = [makeStock(alert: PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))]

        let saved = sut.saveEdit(stockId: "sh600000", cost: nil, shares: nil,
                                 alertTargetText: "9.5.", alertEnabled: true, now: date(10, 0))
        XCTAssertNil(saved)
        XCTAssertNil(sut.stocks[0].alert)
    }

    func test_saveEdit_onlyHoldingChanged_keepsAlertDirection() {
        // 价格已越过目标价（9.4 < 9.5，还没触发），只改成本价，方向不能翻成"涨到"
        sut.stocks = [makeStock(alert: PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))]
        setPrice(9.4)

        sut.saveEdit(stockId: "sh600000", cost: 8, shares: 100,
                     alertTargetText: "9.5", alertEnabled: true, now: date(10, 0))
        XCTAssertEqual(sut.stocks[0].alert?.direction, .fall)
    }

    func test_saveEdit_duringCallAuction_leavesDirectionForLater() {
        sut.stocks = [makeStock()]
        setPrice(10)

        let saved = sut.saveEdit(stockId: "sh600000", cost: nil, shares: nil,
                                 alertTargetText: "9.5", alertEnabled: true, now: date(9, 20))
        XCTAssertNil(saved?.direction)
        XCTAssertEqual(saved?.isEnabled, true)
    }

    func test_saveEdit_unknownStock_changesNothing() {
        sut.stocks = [makeStock()]

        XCTAssertNil(sut.saveEdit(stockId: "sh999999", cost: 1, shares: 1,
                                  alertTargetText: "9.5", alertEnabled: true, now: date(10, 0)))
        XCTAssertEqual(sut.stocks, [makeStock()])
    }

    func test_editedAlert_noQuote_leavesDirectionNil() {
        let a = sut.editedAlert(for: makeStock(), targetText: "9.5", isEnabled: true, now: date(10, 0))
        XCTAssertEqual(a, PriceAlert(targetPrice: 9.5, direction: nil, isEnabled: true))
    }
}
