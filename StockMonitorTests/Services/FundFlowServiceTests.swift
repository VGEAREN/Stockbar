import XCTest
@testable import Stockbar

final class FundFlowServiceTests: XCTestCase {

    func test_parseEastmoneyFundFlow_returns_main_net_inflow() throws {
        let json = """
        {
          "rc": 0,
          "data": {
            "diff": [
              {
                "f12": "603986",
                "f14": "兆易创新",
                "f7": 6.68,
                "f8": 3.21,
                "f10": 2.15,
                "f62": -323225856.0,
                "f64": 25000000.0,
                "f65": 100000000.0,
                "f66": -75000000.0,
                "f69": -3.21,
                "f70": 86000000.0,
                "f71": 42000000.0,
                "f72": 44000000.0,
                "f75": 2.18,
                "f76": 32000000.0,
                "f77": 64000000.0,
                "f78": -32000000.0,
                "f81": -0.81,
                "f82": 71000000.0,
                "f83": 53000000.0,
                "f84": 18000000.0,
                "f87": 1.84,
                "f100": "半导体",
                "f124": 1783485809
              }
            ]
          }
        }
        """
        let result = try XCTUnwrap(FundFlowService.parseEastmoneyFundFlow(Data(json.utf8)))
        XCTAssertEqual(result.mainNetInflow, -323225856.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.turnoverRate), 3.21, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.volumeRatio), 2.15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.amplitude), 6.68, accuracy: 0.001)
        XCTAssertEqual(result.updateTime, "2026-07-08 12:43:29")
        XCTAssertEqual(result.primarySectorName, "半导体")
        XCTAssertEqual(result.orderFlows.map(\.size), FundFlowOrderSize.allCases)

        let superLarge = result.orderFlows[0]
        XCTAssertEqual(try XCTUnwrap(superLarge.inflow), 25000000.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(superLarge.outflow), 100000000.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(superLarge.netInflow), -75000000.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(superLarge.netRatio), -3.21, accuracy: 0.001)

        let large = result.orderFlows[1]
        XCTAssertEqual(try XCTUnwrap(large.inflow), 86000000.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(large.outflow), 42000000.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(large.netInflow), 44000000.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(large.netRatio), 2.18, accuracy: 0.001)
    }

    func test_parseEastmoneyFundFlow_invalid_data() {
        XCTAssertNil(FundFlowService.parseEastmoneyFundFlow(Data("not json".utf8)))
    }

    func test_parseEastmoneyFundFlow_allows_missing_market_metrics() throws {
        let json = """
        {
          "data": {
            "diff": [
              { "f62": 1000, "f124": 1783485809 }
            ]
          }
        }
        """
        let result = try XCTUnwrap(FundFlowService.parseEastmoneyFundFlow(Data(json.utf8)))
        XCTAssertNil(result.turnoverRate)
        XCTAssertNil(result.volumeRatio)
        XCTAssertNil(result.amplitude)
        XCTAssertTrue(result.orderFlows.allSatisfy {
            $0.inflow == nil && $0.outflow == nil && $0.netInflow == nil && $0.netRatio == nil
        })
    }

    func test_parseEastmoneyFundFlowTrend_returns_minute_cumulative_values() throws {
        let json = """
        {
          "data": {
            "klines": [
              "2026-07-16 09:31,11796116.0,0.0,-11670316.0,9052131.0,2743985.0",
              "2026-07-16 09:32,25215991.0,-37791.0,-25051998.0,34821255.0,-9605264.0"
            ]
          }
        }
        """

        let result = try XCTUnwrap(FundFlowService.parseEastmoneyFundFlowTrend(Data(json.utf8)))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].time, "2026-07-16 09:31")
        XCTAssertEqual(result[0].mainNetInflow, 11796116.0, accuracy: 0.001)
        XCTAssertEqual(result[0].smallNetInflow, 0, accuracy: 0.001)
        XCTAssertEqual(result[0].mediumNetInflow, -11670316.0, accuracy: 0.001)
        XCTAssertEqual(result[0].largeNetInflow, 9052131.0, accuracy: 0.001)
        XCTAssertEqual(result[0].superLargeNetInflow, 2743985.0, accuracy: 0.001)
    }

    func test_aggregateMainFundFlowByThirtyMinutes_uses_interval_deltas_and_skips_lunch() {
        let points = [
            minutePoint("2026-07-16 09:31", 10),
            minutePoint("2026-07-16 10:00", 100),
            minutePoint("2026-07-16 10:15", 70),
            minutePoint("2026-07-16 10:30", 40),
            minutePoint("2026-07-16 11:00", 40),
            minutePoint("2026-07-16 11:30", -20),
            minutePoint("2026-07-16 13:15", 30),
            minutePoint("2026-07-16 13:30", 80),
        ]

        let result = FundFlowService.aggregateMainFundFlowByThirtyMinutes(points)

        XCTAssertEqual(result.map(\.startTime), ["09:30", "10:00", "10:30", "11:00", "13:00"])
        XCTAssertEqual(result[0].netInflow, 100, accuracy: 0.001)
        XCTAssertEqual(result[1].netInflow, -60, accuracy: 0.001)
        XCTAssertEqual(result[2].netInflow, 0, accuracy: 0.001)
        XCTAssertEqual(result[3].netInflow, -60, accuracy: 0.001)
        XCTAssertEqual(result[4].netInflow, 100, accuracy: 0.001)
    }

    func test_parseEastmoneyFundFlowTrend_invalid_data() {
        XCTAssertNil(FundFlowService.parseEastmoneyFundFlowTrend(Data("not json".utf8)))
    }

    func test_volumeRatioLevel_boundaries() {
        XCTAssertEqual(VolumeRatioLevel(ratio: 0.49), .quiet)
        XCTAssertEqual(VolumeRatioLevel(ratio: 0.5), .low)
        XCTAssertEqual(VolumeRatioLevel(ratio: 0.8), .normal)
        XCTAssertEqual(VolumeRatioLevel(ratio: 1.5), .active)
        XCTAssertEqual(VolumeRatioLevel(ratio: 2.5), .high)
        XCTAssertEqual(VolumeRatioLevel(ratio: 5.0), .extreme)
    }

    func test_volumeRatioLevel_displayNames() {
        XCTAssertEqual(VolumeRatioLevel(ratio: 0.49).displayName, "清淡")
        XCTAssertEqual(VolumeRatioLevel(ratio: 0.5).displayName, "偏低")
        XCTAssertEqual(VolumeRatioLevel(ratio: 0.8).displayName, "正常")
        XCTAssertEqual(VolumeRatioLevel(ratio: 1.5).displayName, "活跃")
        XCTAssertEqual(VolumeRatioLevel(ratio: 2.5).displayName, "放量")
        XCTAssertEqual(VolumeRatioLevel(ratio: 5.0).displayName, "极端")
    }

    func test_turnoverRateLevel_boundaries() {
        XCTAssertEqual(TurnoverRateLevel(rate: 0.49), .quiet)
        XCTAssertEqual(TurnoverRateLevel(rate: 0.5), .low)
        XCTAssertEqual(TurnoverRateLevel(rate: 1.0), .normal)
        XCTAssertEqual(TurnoverRateLevel(rate: 3.0), .active)
        XCTAssertEqual(TurnoverRateLevel(rate: 7.0), .high)
        XCTAssertEqual(TurnoverRateLevel(rate: 15.0), .extreme)
    }

    func test_turnoverRateLevel_displayNames() {
        XCTAssertEqual(TurnoverRateLevel(rate: 0.49).displayName, "清淡")
        XCTAssertEqual(TurnoverRateLevel(rate: 0.5).displayName, "偏低")
        XCTAssertEqual(TurnoverRateLevel(rate: 1.0).displayName, "正常")
        XCTAssertEqual(TurnoverRateLevel(rate: 3.0).displayName, "活跃")
        XCTAssertEqual(TurnoverRateLevel(rate: 7.0).displayName, "高换手")
        XCTAssertEqual(TurnoverRateLevel(rate: 15.0).displayName, "极端")
    }

    func test_parseEastmoneySector_returns_primary_sector() throws {
        let json = """
        {
          "rc": 0,
          "data": {
            "diff": [
              { "f12": "BK1036", "f14": "半导体", "f3": -0.88 },
              { "f12": "BK1331", "f14": "数字芯片设计", "f3": -0.46 }
            ]
          }
        }
        """

        let result = try XCTUnwrap(FundFlowService.parseEastmoneySector(Data(json.utf8)))
        XCTAssertEqual(result.name, "半导体")
        XCTAssertEqual(result.changePercent, -0.88, accuracy: 0.001)
        XCTAssertEqual(result.formattedPercent, "-0.88%")
        let sectors = try XCTUnwrap(FundFlowService.parseEastmoneySectors(Data(json.utf8)))
        XCTAssertEqual(sectors.map(\.name), ["半导体", "数字芯片设计"])
        XCTAssertEqual(
            FundFlowService.primarySector(from: sectors, matching: "数字芯片设计")?.name,
            "数字芯片设计"
        )
        XCTAssertEqual(
            FundFlowService.primarySector(from: sectors, matching: "不存在的板块")?.name,
            "半导体"
        )
    }

    func test_parseEastmoneySector_supports_dictionary_diff() throws {
        let json = """
        {
          "rc": 0,
          "data": {
            "diff": {
              "1": { "f12": "BK1201", "f14": "电子", "f3": 0.31 },
              "0": { "f12": "BK1036", "f14": "半导体", "f3": 1.25 }
            }
          }
        }
        """

        let result = try XCTUnwrap(FundFlowService.parseEastmoneySector(Data(json.utf8)))
        XCTAssertEqual(result.name, "半导体")
        XCTAssertEqual(result.changePercent, 1.25, accuracy: 0.001)
        XCTAssertEqual(result.formattedPercent, "+1.25%")
    }

    func test_parseEastmoneySector_invalid_data() {
        XCTAssertNil(FundFlowService.parseEastmoneySector(Data("not json".utf8)))
    }

    func test_eastmoneySecid() {
        XCTAssertEqual(FundFlowService.eastmoneySecid(for: "sh603986"), "1.603986")
        XCTAssertEqual(FundFlowService.eastmoneySecid(for: "sz002281"), "0.002281")
        XCTAssertEqual(FundFlowService.eastmoneySecid(for: "bj430047"), "0.430047")
        XCTAssertNil(FundFlowService.eastmoneySecid(for: "usr_aapl"))
    }

    private func minutePoint(_ time: String, _ mainNetInflow: Double) -> FundFlowMinutePoint {
        FundFlowMinutePoint(
            time: time,
            mainNetInflow: mainNetInflow,
            smallNetInflow: 0,
            mediumNetInflow: 0,
            largeNetInflow: 0,
            superLargeNetInflow: 0
        )
    }
}
