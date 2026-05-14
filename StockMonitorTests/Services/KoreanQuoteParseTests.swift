import XCTest
@testable import Stockbar

final class KoreanQuoteParseTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture \(name).json missing — re-run capture step")
        }
        return try Data(contentsOf: url)
    }

    func test_parseKoreanChartMeta_kospi() throws {
        let data = try loadFixture("quote_005930_ks")
        let quote = try XCTUnwrap(DataService.parseKoreanChartMeta(data, id: "kr_005930.ks"))
        XCTAssertEqual(quote.code, "kr_005930.ks")
        XCTAssertGreaterThan(quote.price, 0)
        let prev = quote.price - quote.change
        XCTAssertGreaterThan(prev, 0)
        XCTAssertEqual(quote.changePercent, (quote.price - prev) / prev * 100, accuracy: 0.01)
    }

    func test_parseKoreanChartMeta_kosdaq() throws {
        let data = try loadFixture("quote_293490_kq")
        let quote = try XCTUnwrap(DataService.parseKoreanChartMeta(data, id: "kr_293490.kq"))
        XCTAssertEqual(quote.code, "kr_293490.kq")
        XCTAssertGreaterThan(quote.price, 0)
    }

    func test_parseKoreanChartMeta_emptyPrices_returnsNil() throws {
        let data = try loadFixture("quote_empty")
        XCTAssertNil(DataService.parseKoreanChartMeta(data, id: "kr_999999.ks"))
    }

    func test_parseKoreanChartMeta_garbageData_returnsNil() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(DataService.parseKoreanChartMeta(data, id: "kr_005930.ks"))
    }
}
