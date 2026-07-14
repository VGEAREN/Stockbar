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
                "f62": -323225856.0,
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
        XCTAssertEqual(try XCTUnwrap(result.amplitude), 6.68, accuracy: 0.001)
        XCTAssertEqual(result.updateTime, "2026-07-08 12:43:29")
        XCTAssertEqual(result.primarySectorName, "半导体")
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
        XCTAssertNil(result.amplitude)
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
}
