import XCTest
@testable import Stockbar

@MainActor
final class AppStateTests: XCTestCase {
    var sut: AppState!
    var tmpDir: URL!

    override func setUp() {
        super.setUp()
        // CRITICAL: AppState reads/writes ~/Library/Application Support/Stockbar/
        // by default. Without isolation, every test mutation would overwrite the
        // user's real stocks.json. Always redirect to a per-test temp dir.
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StockbarTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        AppState.appSupportDirOverride = tmpDir

        sut = AppState()
        sut.stocks = []
        sut.quotes = [:]
        sut.statusBarStockId = ""
    }

    override func tearDown() {
        sut = nil
        AppState.appSupportDirOverride = nil
        if let d = tmpDir { try? FileManager.default.removeItem(at: d) }
        tmpDir = nil
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

    func test_statusBarStock_mostVolatileSelectsLargestPositiveMove() {
        sut.stocks = [
            Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "股票2", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        sut.quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.1, changePercent: 1.0, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: 0.6, changePercent: 6.0, updateTime: "")
        ]
        sut.statusBarStockId = "__most_volatile__"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600001")
    }

    func test_statusBarStock_mostVolatileSelectsLargestAbsoluteNegativeMove() {
        sut.stocks = [
            Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "股票2", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        sut.quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.5, changePercent: 5.0, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: -0.7, changePercent: -7.0, updateTime: "")
        ]
        sut.statusBarStockId = "__most_volatile__"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600001")
    }

    func test_statusBarStock_mostVolatilePrefersNegativeWhenAbsoluteMoveTies() {
        sut.stocks = [
            Stock(id: "sh600000", name: "上涨", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "下跌", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        sut.quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.7, changePercent: 7.0, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: -0.7, changePercent: -7.0, updateTime: "")
        ]
        sut.statusBarStockId = "__most_volatile__"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600001")
    }

    func test_statusBarStock_mostVolatileFallsBackToFirstWithoutQuotes() {
        let s = Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil)
        sut.stocks = [s]
        sut.quotes = [:]
        sut.statusBarStockId = "__most_volatile__"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600000")
    }

    func test_statusBarStock_mostVolatileIgnoresNonFinitePercent() {
        sut.stocks = [
            Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "股票2", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        sut.quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: .nan, changePercent: .nan, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: 0.3, changePercent: 3.0, updateTime: "")
        ]
        sut.statusBarStockId = "__most_volatile__"
        XCTAssertEqual(sut.statusBarStock?.id, "sh600001")
    }

    func test_statusBarStock_noneModeReturnsNil() {
        sut.stocks = [Stock(id: "sh600000", name: "股票1", market: .aStock, costPrice: nil, holdingShares: nil)]
        sut.statusBarStockId = "__none__"
        XCTAssertNil(sut.statusBarStock)
    }

    func test_statusBarIconMode_updatesConfig() {
        sut.statusBarIconMode = .stockInitial
        XCTAssertEqual(sut.config.statusBarIconMode, .stockInitial)
    }

    func test_doNotDisturb_sameDayRange() {
        XCTAssertTrue(AppState.isDoNotDisturbActive(
            minuteOfDay: 10 * 60,
            startMinutes: 9 * 60,
            endMinutes: 11 * 60
        ))
        XCTAssertFalse(AppState.isDoNotDisturbActive(
            minuteOfDay: 12 * 60,
            startMinutes: 9 * 60,
            endMinutes: 11 * 60
        ))
    }

    func test_doNotDisturb_crossDayRange() {
        let start = 15 * 60
        let end = 9 * 60 + 30
        XCTAssertTrue(AppState.isDoNotDisturbActive(minuteOfDay: 16 * 60, startMinutes: start, endMinutes: end))
        XCTAssertTrue(AppState.isDoNotDisturbActive(minuteOfDay: 9 * 60, startMinutes: start, endMinutes: end))
        XCTAssertFalse(AppState.isDoNotDisturbActive(minuteOfDay: 10 * 60, startMinutes: start, endMinutes: end))
    }

    func test_doNotDisturb_sameStartAndEndMeansAllDay() {
        XCTAssertTrue(AppState.isDoNotDisturbActive(
            minuteOfDay: 12 * 60,
            startMinutes: 8 * 60,
            endMinutes: 8 * 60
        ))
    }

    func test_doNotDisturb_usesConfigEnabledFlag() {
        sut.config.doNotDisturbEnabled = false
        sut.config.doNotDisturbStartMinutes = 15 * 60
        sut.config.doNotDisturbEndMinutes = 9 * 60 + 30
        XCTAssertFalse(sut.isDoNotDisturbActive(at: makeDate(hour: 16, minute: 0)))

        sut.config.doNotDisturbEnabled = true
        XCTAssertTrue(sut.isDoNotDisturbActive(at: makeDate(hour: 16, minute: 0)))
    }

    func test_volatilityAlertCandidates_includePositiveAndNegativeMovesOverThreshold() {
        let stocks = [
            Stock(id: "sh600000", name: "上涨", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "下跌", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600002", name: "未触发", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        let quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.6, changePercent: 6.0, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: -0.7, changePercent: -7.0, updateTime: ""),
            "sh600002": Quote(code: "sh600002", price: 10.0, change: 0.3, changePercent: 3.0, updateTime: "")
        ]

        let candidates = AppState.volatilityAlertCandidates(
            stocks: stocks,
            quotes: quotes,
            threshold: 5.0,
            alertedStockIds: []
        )

        XCTAssertEqual(candidates.map(\.stockId), ["sh600000", "sh600001"])
    }

    func test_volatilityAlertCandidates_useManualFractionalThreshold() {
        let stocks = [
            Stock(id: "sh600000", name: "触发", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "未触发", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        let quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.09, changePercent: 0.9, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: 0.07, changePercent: 0.7, updateTime: "")
        ]

        let candidates = AppState.volatilityAlertCandidates(
            stocks: stocks,
            quotes: quotes,
            threshold: 0.8,
            alertedStockIds: []
        )

        XCTAssertEqual(candidates.map(\.stockId), ["sh600000"])
        XCTAssertEqual(candidates.first?.threshold, 0.8, accuracy: 0.001)
    }

    func test_volatilityAlertCandidates_skipAlreadyAlertedStocks() {
        let stocks = [Stock(id: "sh600000", name: "上涨", market: .aStock, costPrice: nil, holdingShares: nil)]
        let quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.6, changePercent: 6.0, updateTime: "")
        ]

        let candidates = AppState.volatilityAlertCandidates(
            stocks: stocks,
            quotes: quotes,
            threshold: 5.0,
            alertedStockIds: ["sh600000"]
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func test_volatilityAlertActiveStockIds_dropStocksBackUnderThreshold() {
        let stocks = [
            Stock(id: "sh600000", name: "上涨", market: .aStock, costPrice: nil, holdingShares: nil),
            Stock(id: "sh600001", name: "回落", market: .aStock, costPrice: nil, holdingShares: nil)
        ]
        let quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: 0.6, changePercent: 6.0, updateTime: ""),
            "sh600001": Quote(code: "sh600001", price: 10.0, change: 0.3, changePercent: 3.0, updateTime: "")
        ]

        let activeIds = AppState.volatilityAlertActiveStockIds(
            stocks: stocks,
            quotes: quotes,
            threshold: 5.0
        )

        XCTAssertEqual(activeIds, ["sh600000"])
    }

    func test_volatilityAlertCandidates_ignoreNonFinitePercent() {
        let stocks = [Stock(id: "sh600000", name: "异常", market: .aStock, costPrice: nil, holdingShares: nil)]
        let quotes = [
            "sh600000": Quote(code: "sh600000", price: 10.0, change: .nan, changePercent: .nan, updateTime: "")
        ]

        let candidates = AppState.volatilityAlertCandidates(
            stocks: stocks,
            quotes: quotes,
            threshold: 5.0,
            alertedStockIds: []
        )

        XCTAssertTrue(candidates.isEmpty)
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

    func test_effectiveShares_activeWatchlistOverridesRealHolding() {
        let stock = Stock(
            id: "sh600000",
            name: "股票1",
            market: .aStock,
            costPrice: 10.0,
            holdingShares: 100
        )
        let watchlist = Watchlist(
            id: "watchlist-1",
            name: "观察仓",
            entries: [stock.id: WatchlistEntry(costPrice: 11.0, holdingShares: 250)]
        )
        sut.stocks = [stock]
        sut.watchlists = [watchlist]
        sut.config.activeWatchlistId = watchlist.id

        XCTAssertEqual(sut.effectiveShares(for: stock), 250)
    }

    func test_effectiveShares_zeroSharesIsNotAPositiveHolding() {
        let stock = Stock(
            id: "sh600000",
            name: "股票1",
            market: .aStock,
            costPrice: 10.0,
            holdingShares: 0
        )
        sut.stocks = [stock]

        XCTAssertEqual(sut.effectiveShares(for: stock), 0)
        XCTAssertFalse((sut.effectiveShares(for: stock) ?? 0) > 0)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.year = 2026
        comps.month = 6
        comps.day = 25
        comps.hour = hour
        comps.minute = minute
        return comps.date!
    }
}
