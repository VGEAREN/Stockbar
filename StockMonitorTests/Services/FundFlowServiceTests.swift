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
                "f62": -323225856.0,
                "f124": 1783485809
              }
            ]
          }
        }
        """
        let result = try XCTUnwrap(FundFlowService.parseEastmoneyFundFlow(Data(json.utf8)))
        XCTAssertEqual(result.mainNetInflow, -323225856.0, accuracy: 0.001)
        XCTAssertEqual(result.updateTime, "2026-07-08 12:43:29")
    }

    func test_parseEastmoneyFundFlow_invalid_data() {
        XCTAssertNil(FundFlowService.parseEastmoneyFundFlow(Data("not json".utf8)))
    }

    func test_eastmoneySecid() {
        XCTAssertEqual(FundFlowService.eastmoneySecid(for: "sh603986"), "1.603986")
        XCTAssertEqual(FundFlowService.eastmoneySecid(for: "sz002281"), "0.002281")
        XCTAssertEqual(FundFlowService.eastmoneySecid(for: "bj430047"), "0.430047")
        XCTAssertNil(FundFlowService.eastmoneySecid(for: "usr_aapl"))
    }
}
