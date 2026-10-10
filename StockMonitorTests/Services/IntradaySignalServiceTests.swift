import Foundation
import XCTest
@testable import Stockbar

final class IntradaySignalServiceTests: XCTestCase {

    func test_attacking_maps_holding_and_nonholding_actions() {
        let prices = linearPrices(from: 100, to: 101.5, count: 40)

        let holding = evaluate(prices, volumeRatio: 1.2, isHolding: true)
        let nonholding = evaluate(prices, volumeRatio: 1.2, isHolding: false)

        XCTAssertEqual(holding.state, .attacking)
        XCTAssertEqual(holding.displayText, "上攻/持有")
        XCTAssertEqual(nonholding.state, .attacking)
        XCTAssertEqual(nonholding.displayText, "上攻/勿追")
        XCTAssertEqual(holding.colorRole, .up)
    }

    func test_fallingBack_has_priority_over_weak_score() {
        var prices = linearPrices(from: 100, to: 101.5, count: 10)
        prices += Array(repeating: 101.4, count: 24)
        prices += linearPrices(from: 101.4, to: 100.5, count: 6)

        let signal = evaluate(prices, volumeRatio: 1.3, isHolding: true)

        XCTAssertEqual(signal.state, .fallingBack)
        XCTAssertEqual(signal.displayText, "回落/谨慎")
        XCTAssertEqual(signal.colorRole, .down)
    }

    func test_recovering_detects_rebound_from_intraday_low() {
        var prices = linearPrices(from: 100, to: 99.0, count: 11)
        prices += Array(repeating: 99.1, count: 14)
        prices += linearPrices(from: 99.1, to: 100.2, count: 15)

        let signal = evaluate(prices, volumeRatio: 1.1, isHolding: false)

        XCTAssertEqual(signal.state, .recovering)
        XCTAssertEqual(signal.displayText, "回升/关注")
    }

    func test_declining_requires_directional_confirmation() {
        let prices = linearPrices(from: 100, to: 98.5, count: 40)

        let confirmed = evaluate(prices, volumeRatio: 1.2, isHolding: true)
        let unconfirmed = evaluate(
            prices,
            volumeRatio: 0.7,
            mainNetInflow: 1_000,
            isHolding: true
        )

        XCTAssertEqual(confirmed.state, .declining)
        XCTAssertEqual(confirmed.displayText, "下行/风控")
        XCTAssertEqual(unconfirmed.state, .relativelyWeak)
        XCTAssertEqual(unconfirmed.displayText, "偏弱/谨慎")
    }

    func test_pullingBack_detects_short_drop_inside_longer_uptrend() {
        var prices = linearPrices(from: 100, to: 101.5, count: 31)
        prices += Array(repeating: 101.5, count: 14)
        prices += linearPrices(from: 101.5, to: 101.35, count: 5)

        let signal = evaluate(prices, volumeRatio: 0.9, isHolding: false)

        XCTAssertEqual(signal.state, .pullingBack)
        XCTAssertEqual(signal.displayText, "回踩/等稳")
        XCTAssertEqual(signal.colorRole, .warning)
    }

    func test_rebounding_detects_short_rise_inside_longer_decline() {
        var prices = linearPrices(from: 100, to: 99.5, count: 21)
        prices += linearPrices(from: 99.5, to: 98.0, count: 20)
        prices += Array(repeating: 98.0, count: 4)
        prices += linearPrices(from: 98.0, to: 98.4, count: 5)

        let signal = evaluate(prices, volumeRatio: 0.8, isHolding: false)

        XCTAssertEqual(signal.state, .rebounding)
        XCTAssertEqual(signal.displayText, "反抽/勿追")
        XCTAssertEqual(signal.colorRole, .warning)
    }

    func test_fallback_classifies_strong_weak_and_sideways() {
        let strong = evaluate(
            linearPrices(from: 100, to: 101.2, count: 40),
            volumeRatio: 0.7,
            mainNetInflow: -1,
            isHolding: false
        )
        let weak = evaluate(
            linearPrices(from: 100, to: 98.8, count: 40),
            volumeRatio: 0.7,
            mainNetInflow: 1,
            isHolding: false
        )
        let sideways = evaluate(Array(repeating: 100, count: 40), isHolding: false)

        XCTAssertEqual(strong.state, .relativelyStrong)
        XCTAssertEqual(strong.displayText, "偏强/观察")
        XCTAssertEqual(weak.state, .relativelyWeak)
        XCTAssertEqual(weak.displayText, "偏弱/回避")
        XCTAssertEqual(sideways.state, .sideways)
        XCTAssertEqual(sideways.displayText, "震荡/观望")
        XCTAssertEqual(sideways.metrics?.dayPosition, 0.5)
    }

    func test_opening_and_missing_momentum_are_safe() {
        let tooFew = evaluate(Array(repeating: 100, count: 15), isHolding: true)
        let missingMomentum = evaluate(
            (0..<20).map { MinutePoint(id: $0 / 2, time: "", price: 100) },
            isHolding: true
        )
        let sparse = evaluate(
            (0..<20).map { MinutePoint(id: $0 * 2, time: "", price: 100) },
            isHolding: true
        )

        XCTAssertEqual(tooFew.state, .opening)
        XCTAssertEqual(tooFew.displayText, "开盘/观察")
        XCTAssertEqual(missingMomentum.state, .opening)
        XCTAssertEqual(sparse.state, .sideways)
    }

    func test_session_and_stale_data_states() {
        let prices = linearPrices(from: 100, to: 101, count: 40)
        let preOpen = evaluate(prices, now: date(hour: 9, minute: 10), quoteIsToday: false)
        let lunch = evaluate(prices, now: date(hour: 12), quoteIsToday: true)
        let closed = evaluate(prices, now: date(hour: 15, minute: 10), quoteIsToday: true)
        let weekend = evaluate(prices, now: date(day: 18, hour: 10), quoteIsToday: false)
        let stale = evaluate(prices, intradayAge: 181)

        XCTAssertEqual(preOpen.displayText, "待开/观察")
        XCTAssertEqual(lunch.displayText, "午休/观察")
        XCTAssertEqual(closed.displayText, "收盘/复盘")
        XCTAssertEqual(weekend.displayText, "休市/复盘")
        XCTAssertEqual(stale.displayText, "数据/等待")
    }

    func test_stale_fund_flow_is_removed_from_signal_and_help() {
        let signal = evaluate(
            linearPrices(from: 100, to: 101.5, count: 40),
            volumeRatio: 1.5,
            mainNetInflow: 1_000_000,
            sectorChangePercent: 2.0,
            isHolding: true,
            fundFlowAge: 31,
            fundFlowMaxAge: 30
        )

        XCTAssertNotEqual(signal.state, .attacking)
        XCTAssertNil(signal.metrics?.volumeRatio)
        XCTAssertNil(signal.metrics?.mainNetInflow)
        XCTAssertNil(signal.metrics?.sectorChangePercent)
        XCTAssertFalse(signal.helpText.contains("资金方向"))
        XCTAssertTrue(signal.helpText.contains("操作仅供盘面参考"))
    }

    func test_stabilizer_requires_two_matching_updates_to_change_live_state() {
        var stabilizer = IntradaySignalStabilizer()
        let attacking = signal(state: .attacking, action: .hold)
        let sideways = signal(state: .sideways, action: .stayOut)

        XCTAssertEqual(stabilizer.update(attacking).state, .attacking)
        XCTAssertEqual(stabilizer.update(sideways).state, .attacking)
        XCTAssertEqual(stabilizer.update(sideways).state, .sideways)
    }

    func test_stabilizer_updates_action_immediately_when_state_is_unchanged() {
        var stabilizer = IntradaySignalStabilizer()

        XCTAssertEqual(stabilizer.update(signal(state: .attacking, action: .hold)).action, .hold)
        XCTAssertEqual(
            stabilizer.update(signal(state: .attacking, action: .doNotChase)).action,
            .doNotChase
        )
    }

    // MARK: - Helpers

    private func evaluate(
        _ prices: [Double],
        volumeRatio: Double? = 1.0,
        mainNetInflow: Double? = 1_000,
        sectorChangePercent: Double? = 0.5,
        isHolding: Bool = false,
        now: Date? = nil,
        quoteIsToday: Bool = true,
        intradayAge: TimeInterval = 0,
        fundFlowAge: TimeInterval = 0,
        fundFlowMaxAge: TimeInterval = 30
    ) -> IntradaySignal {
        evaluate(
            prices.enumerated().map { MinutePoint(id: $0.offset, time: "", price: $0.element) },
            volumeRatio: volumeRatio,
            mainNetInflow: mainNetInflow,
            sectorChangePercent: sectorChangePercent,
            isHolding: isHolding,
            now: now,
            quoteIsToday: quoteIsToday,
            intradayAge: intradayAge,
            fundFlowAge: fundFlowAge,
            fundFlowMaxAge: fundFlowMaxAge
        )
    }

    private func evaluate(
        _ points: [MinutePoint],
        volumeRatio: Double? = 1.0,
        mainNetInflow: Double? = 1_000,
        sectorChangePercent: Double? = 0.5,
        isHolding: Bool = false,
        now: Date? = nil,
        quoteIsToday: Bool = true,
        intradayAge: TimeInterval = 0,
        fundFlowAge: TimeInterval = 0,
        fundFlowMaxAge: TimeInterval = 30
    ) -> IntradaySignal {
        let resolvedNow = now ?? date(hour: 10, minute: 30)
        return IntradaySignalService.evaluate(
            IntradaySignalInput(
                points: points,
                currentPrice: points.last?.price,
                quoteIsToday: quoteIsToday,
                preClose: 100,
                volumeRatio: volumeRatio,
                mainNetInflow: mainNetInflow,
                sectorChangePercent: sectorChangePercent,
                isHolding: isHolding,
                now: resolvedNow,
                intradayLoadedAt: resolvedNow.addingTimeInterval(-intradayAge),
                fundFlowLoadedAt: resolvedNow.addingTimeInterval(-fundFlowAge),
                fundFlowMaxAge: fundFlowMaxAge
            )
        )
    }

    private func linearPrices(from start: Double, to end: Double, count: Int) -> [Double] {
        guard count > 1 else { return [end] }
        return (0..<count).map { index in
            start + (end - start) * Double(index) / Double(count - 1)
        }
    }

    private func signal(state: IntradayState, action: IntradayAction) -> IntradaySignal {
        IntradaySignal(
            state: state,
            action: action,
            colorRole: .neutral,
            metrics: nil,
            updatedAt: date(hour: 10, minute: 30)
        )
    }

    private static func date(day: Int = 14, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(
            from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute)
        )!
    }

    private func date(day: Int = 14, hour: Int, minute: Int = 0) -> Date {
        Self.date(day: day, hour: hour, minute: minute)
    }
}
