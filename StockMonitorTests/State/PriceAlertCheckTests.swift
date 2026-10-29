import XCTest
@testable import Stockbar

/// 记录发出的到价通知；authorized 控制"有没有通知权限"
@MainActor
private final class FakeNotifier: PriceAlertNotifier {
    var authorized = true
    private(set) var hits: [PriceAlertHit] = []
    func isAuthorized() async -> Bool { authorized }
    func notifyPriceReached(_ hit: PriceAlertHit) { hits.append(hit) }
}

@MainActor
final class PriceAlertCheckTests: XCTestCase {
    var sut: AppState!
    var tmpDir: URL!
    private var notifier: FakeNotifier!

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
        notifier = FakeNotifier()
        sut.notifier = notifier
    }

    override func tearDown() {
        sut = nil
        notifier = nil
        AppState.appSupportDirOverride = nil
        if let d = tmpDir { try? FileManager.default.removeItem(at: d) }
        tmpDir = nil
        super.tearDown()
    }

    // MARK: - 辅助

    private func date(_ tz: String, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: tz)!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// 2026-10-29（周四）北京时间 10:00，A股盘中
    private var aStockOpen: Date { date("Asia/Shanghai", 2026, 10, 29, 10, 0) }

    private let fallTo9_5 = PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true)

    private func stock(_ id: String, _ market: Market, _ alert: PriceAlert?) -> Stock {
        Stock(id: id, name: "股票\(id)", market: market, costPrice: nil, holdingShares: nil, alert: alert)
    }

    private func quote(_ id: String, _ price: Double, ext: Double? = nil) -> Quote {
        Quote(code: id, price: price, change: 0, changePercent: 0, updateTime: "", extendedPrice: ext)
    }

    private func savedStocks() throws -> [Stock] {
        let data = try Data(contentsOf: tmpDir.appendingPathComponent("stocks.json"))
        return try JSONDecoder().decode([Stock].self, from: data)
    }

    // MARK: - 触发

    func test_reached_notifiesOnceAndTurnsOff() async {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(notifier.hits, [PriceAlertHit(stockId: "sh600000", stockName: "股票sh600000",
                                                     price: 9.4, targetPrice: 9.5,
                                                     direction: .fall, sessionLabel: nil)])
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, false)

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(notifier.hits.count, 1, "只通知一次")
    }

    func test_reached_savesTurnedOffAlertToDisk() async throws {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(try savedStocks().first?.alert?.isEnabled, false)
    }

    func test_notReached_staysOn() async {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.6)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, true)
    }

    func test_noPermission_doesNotFireAndStaysOn() async {
        notifier.authorized = false
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, true)
    }

    func test_disabledAlert_isIgnored() async {
        sut.stocks = [stock("sh600000", .aStock, PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: false))]
        sut.quotes = ["sh600000": quote("sh600000", 9.0)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
    }

    func test_missingQuote_isSkipped() async {
        sut.stocks = [stock("sh600000", .aStock, PriceAlert(targetPrice: 9.5, direction: nil, isEnabled: true))]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertNil(sut.stocks[0].alert?.direction)
    }

    func test_nilDirection_isSetFromFirstPriceAndSaved() async throws {
        sut.stocks = [stock("sh600000", .aStock, PriceAlert(targetPrice: 9.5, direction: nil, isEnabled: true))]
        sut.quotes = ["sh600000": quote("sh600000", 10)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(sut.stocks[0].alert?.direction, .fall)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(try savedStocks().first?.alert?.direction, .fall)
    }

    func test_multipleStocksReached_eachNotified() async {
        sut.stocks = [
            stock("sh600000", .aStock, fallTo9_5),
            stock("hk00700", .hkStock, PriceAlert(targetPrice: 400, direction: .rise, isEnabled: true)),
        ]
        sut.quotes = ["sh600000": quote("sh600000", 9.4), "hk00700": quote("hk00700", 401)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(Set(notifier.hits.map(\.stockId)), ["sh600000", "hk00700"])
        XCTAssertEqual(sut.stocks.map { $0.alert?.isEnabled }, [false, false])
    }

    // MARK: - 美股用哪个价格

    func test_usRegularSession_usesRegularPrice() async {
        // 2026-10-29（周四）ET 10:00 盘中：时段价（盘前遗留）不参与
        sut.stocks = [stock("usr_aapl", .usStock, PriceAlert(targetPrice: 182, direction: .rise, isEnabled: true))]
        sut.quotes = ["usr_aapl": quote("usr_aapl", 181, ext: 183)]

        await sut.checkPriceAlerts(now: date("America/New_York", 2026, 10, 29, 10, 0))
        XCTAssertTrue(notifier.hits.isEmpty)
    }

    func test_usAfterHours_usesExtendedPriceWithLabel() async {
        // 2026-10-29（周四）ET 17:00 盘后
        sut.stocks = [stock("usr_aapl", .usStock, PriceAlert(targetPrice: 182, direction: .rise, isEnabled: true))]
        sut.quotes = ["usr_aapl": quote("usr_aapl", 181, ext: 182.3)]

        await sut.checkPriceAlerts(now: date("America/New_York", 2026, 10, 29, 17, 0))
        XCTAssertEqual(notifier.hits.first?.price, 182.3)
        XCTAssertEqual(notifier.hits.first?.sessionLabel, "盘后")
    }

    func test_alertPrice_usWeekend_usesExtendedPriceLabelledAfterHours() {
        // 2026-10-31（周六）休市：用周五盘后价，标「盘后」
        let p = AppState.alertPrice(for: stock("usr_aapl", .usStock, nil),
                                    quote: quote("usr_aapl", 181, ext: 182.3),
                                    now: date("America/New_York", 2026, 10, 31, 12, 0))
        XCTAssertEqual(p?.price, 182.3)
        XCTAssertEqual(p?.sessionLabel, "盘后")
    }

    func test_alertPrice_usWithoutExtendedPrice_usesRegularPrice() {
        let p = AppState.alertPrice(for: stock("usr_aapl", .usStock, nil),
                                    quote: quote("usr_aapl", 181),
                                    now: date("America/New_York", 2026, 10, 29, 17, 0))
        XCTAssertEqual(p?.price, 181)
        XCTAssertNil(p?.sessionLabel)
    }

    func test_alertPrice_nonPositivePrice_isNil() {
        XCTAssertNil(AppState.alertPrice(for: stock("hk00700", .hkStock, nil),
                                         quote: quote("hk00700", 0), now: aStockOpen))
    }

    // MARK: - A股集合竞价

    func test_isAStockCallAuction_boundaries() {
        XCTAssertFalse(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 14)))
        XCTAssertTrue(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 15)))
        XCTAssertTrue(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 24)))
        XCTAssertFalse(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 25)))
        // 周六没有竞价
        XCTAssertFalse(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 31, 9, 20)))
    }

    func test_aStockCallAuction_skipsThenFiresFrom0925() async {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: date("Asia/Shanghai", 2026, 10, 29, 9, 20))
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, true)

        await sut.checkPriceAlerts(now: date("Asia/Shanghai", 2026, 10, 29, 9, 25))
        XCTAssertEqual(notifier.hits.count, 1)
    }

    func test_callAuction_onlyAppliesToAStock() async {
        sut.stocks = [stock("hk00700", .hkStock, PriceAlert(targetPrice: 400, direction: .rise, isEnabled: true))]
        sut.quotes = ["hk00700": quote("hk00700", 401)]

        await sut.checkPriceAlerts(now: date("Asia/Shanghai", 2026, 10, 29, 9, 20))
        XCTAssertEqual(notifier.hits.count, 1)
    }
}
