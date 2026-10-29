import XCTest
@testable import Stockbar

@MainActor
final class PriceAlertTests: XCTestCase {

    // MARK: - 方向

    func test_direction_targetAbovePrice_isRise() {
        XCTAssertEqual(PriceAlert.direction(target: 11, currentPrice: 10), .rise)
    }

    func test_direction_targetBelowPrice_isFall() {
        XCTAssertEqual(PriceAlert.direction(target: 9, currentPrice: 10), .fall)
    }

    func test_direction_targetEqualsPrice_isRise() {
        XCTAssertEqual(PriceAlert.direction(target: 10, currentPrice: 10), .rise)
    }

    // MARK: - 到价

    func test_isReached_rise_boundary() {
        let a = PriceAlert(targetPrice: 11, direction: .rise, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 10.99))
        XCTAssertTrue(a.isReached(by: 11))
        XCTAssertTrue(a.isReached(by: 11.5))
    }

    func test_isReached_fall_boundary() {
        let a = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 9.01))
        XCTAssertTrue(a.isReached(by: 9))
        XCTAssertTrue(a.isReached(by: 8.5))
    }

    func test_isReached_falseWhenDisabled() {
        let a = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: false)
        XCTAssertFalse(a.isReached(by: 8))
    }

    func test_isReached_falseWhenDirectionUnknown() {
        let a = PriceAlert(targetPrice: 9, direction: nil, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 8))
    }

    func test_isReached_falseForNonPositivePrice() {
        let a = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 0))
        XCTAssertFalse(a.isReached(by: -1))
    }

    // MARK: - 目标价输入

    func test_parseTarget() {
        XCTAssertEqual(PriceAlert.parseTarget("9.5"), 9.5)
        XCTAssertEqual(PriceAlert.parseTarget(" 12 "), 12)
        XCTAssertNil(PriceAlert.parseTarget(""))
        XCTAssertNil(PriceAlert.parseTarget("abc"))
        XCTAssertNil(PriceAlert.parseTarget("9.5."))
        XCTAssertNil(PriceAlert.parseTarget("0"))
        XCTAssertNil(PriceAlert.parseTarget("-3"))
        XCTAssertNil(PriceAlert.parseTarget("inf"))
    }

    // MARK: - 编辑页保存规则

    func test_edited_newEnabled_setsDirectionFromPrice() {
        let a = PriceAlert.edited(previous: nil, targetPrice: 9, isEnabled: true, currentPrice: 10)
        XCTAssertEqual(a, PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true))
    }

    func test_edited_newWithoutPrice_leavesDirectionNil() {
        let a = PriceAlert.edited(previous: nil, targetPrice: 9, isEnabled: true, currentPrice: nil)
        XCTAssertEqual(a, PriceAlert(targetPrice: 9, direction: nil, isEnabled: true))
    }

    func test_edited_reEnable_recomputesDirection() {
        // 触发后开关已关；现价 8 低于目标 9，再打开时这次应等"涨到"
        let fired = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: false)
        let a = PriceAlert.edited(previous: fired, targetPrice: 9, isEnabled: true, currentPrice: 8)
        XCTAssertEqual(a.direction, .rise)
    }

    func test_edited_changedTarget_recomputesDirection() {
        let prev = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        let a = PriceAlert.edited(previous: prev, targetPrice: 12, isEnabled: true, currentPrice: 10)
        XCTAssertEqual(a.direction, .rise)
    }

    func test_edited_unchangedEnabledAlert_keepsDirection() {
        // 价格已越过目标价（9.4 < 9.5，还没触发），只改成本价保存时方向不能翻成"涨到"
        let prev = PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true)
        let a = PriceAlert.edited(previous: prev, targetPrice: 9.5, isEnabled: true, currentPrice: 9.4)
        XCTAssertEqual(a.direction, .fall)
    }

    func test_edited_disabled_keepsPreviousDirection() {
        let prev = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        let a = PriceAlert.edited(previous: prev, targetPrice: 9, isEnabled: false, currentPrice: 10)
        XCTAssertEqual(a, PriceAlert(targetPrice: 9, direction: .fall, isEnabled: false))
    }

    // MARK: - 文案

    func test_hit_title_and_body_fall() {
        let hit = PriceAlertHit(stockId: "sh600000", stockName: "浦发银行", price: 9.48,
                                targetPrice: 9.5, direction: .fall, sessionLabel: nil)
        XCTAssertEqual(hit.title, "浦发银行 到价提醒")
        XCTAssertEqual(hit.body, "现价 9.480，已跌到目标价 9.500")
    }

    func test_hit_body_usExtendedSession() {
        let hit = PriceAlertHit(stockId: "usr_aapl", stockName: "苹果", price: 182.3,
                                targetPrice: 182, direction: .rise, sessionLabel: "盘后")
        XCTAssertEqual(hit.body, "盘后 182.30，已涨到目标价 182.00")
    }

    func test_summary() {
        XCTAssertEqual(PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true).summary, "跌到 9.500")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: .rise, isEnabled: true).summary, "涨到 11.00")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: nil, isEnabled: true).summary, "目标 11.00")
    }

    func test_badge() {
        XCTAssertEqual(PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true).badge, "↓9.500")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: .rise, isEnabled: true).badge, "↑11.00")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: nil, isEnabled: true).badge, "11.00")
    }
}
