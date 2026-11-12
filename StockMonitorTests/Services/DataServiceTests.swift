import XCTest
@testable import Stockbar

final class DataServiceTests: XCTestCase {

    // MARK: - Sina A股

    func test_parseSina_aStock_basicFields() throws {
        // 新浪 A股格式：名称,今开,昨收,现价,最高,最低,...,日期,时间,...
        let raw = """
        var hq_str_sh600000="浦发银行,9.47,9.46,9.56,9.59,9.43,9.55,9.56,\
        12345678,1234567890.00,100,9.55,200,9.54,300,9.53,400,9.52,500,9.51,\
        100,9.56,200,9.57,300,9.58,400,9.59,500,9.60,2024-01-15,15:00:00,00,浦发银行,上交所,sh";\n
        """
        let quotes = DataService.parseSinaResponse(raw)
        XCTAssertEqual(quotes.count, 1)
        let q = try XCTUnwrap(quotes["sh600000"])
        XCTAssertEqual(q.price, 9.56, accuracy: 0.001)
        // changePercent = (9.56 - 9.46) / 9.46 * 100 ≈ 1.057
        XCTAssertEqual(q.changePercent, (9.56 - 9.46) / 9.46 * 100, accuracy: 0.01)
        XCTAssertTrue(q.updateTime.contains("2024-01-15"))
    }

    func test_parseSina_multipleStocks() {
        let raw = """
        var hq_str_sh600000="浦发银行,9.47,9.46,9.56,9.59,9.43,9.55,9.56,\
        12345678,1234567890.00,100,9.55,200,9.54,300,9.53,400,9.52,500,9.51,\
        100,9.56,200,9.57,300,9.58,400,9.59,500,9.60,2024-01-15,15:00:00,00,浦发银行,上交所,sh";\n\
        var hq_str_sz000001="平安银行,11.80,11.75,12.00,12.05,11.70,11.99,12.00,\
        9876543,987654321.00,100,11.99,200,11.98,300,11.97,400,11.96,500,11.95,\
        100,12.00,200,12.01,300,12.02,400,12.03,500,12.04,2024-01-15,15:00:00,00,平安银行,深交所,sz";\n
        """
        let quotes = DataService.parseSinaResponse(raw)
        XCTAssertEqual(quotes.count, 2)
        XCTAssertNotNil(quotes["sh600000"])
        XCTAssertNotNil(quotes["sz000001"])
    }

    func test_parseSina_emptyResponse() {
        XCTAssertTrue(DataService.parseSinaResponse("").isEmpty)
    }

    func test_parseSina_usStock() throws {
        // 美股格式：名称,现价,涨跌%,更新时间,涨跌额,今开,最高,最低,...,昨收,...
        let raw = """
        var hq_str_usr_aapl="苹果,189.50,-1.50,2024-01-15 17:30:00 EST,-3.49,\
        191.00,192.50,188.00,189.20,186.50,100000,200000,1000000000,3.54,25.0,\
        0,0,0,0,24000000000,50,188.00,-0.25,-0.50,Jan 15 04:30PM EST,Jan 15 04:00PM EST,191.00,\
        300000,1,2024,1234567890,189.30,188.50,50000000,189.00,189.50";\n
        """
        let quotes = DataService.parseSinaResponse(raw)
        let q = try XCTUnwrap(quotes["usr_aapl"])
        XCTAssertEqual(q.price, 189.50, accuracy: 0.001)
    }

    // MARK: - Tencent 港股

    func test_parseTencent_hkStock() throws {
        // 腾讯港股格式: v_r_hk00700="1~腾讯控股~00700~现价~昨收~..."
        let raw = """
        v_r_hk00700="1~腾讯控股~00700~342.00~345.00~341.00~0~0~0~0~0~0~\
        0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~2024-01-15 15:58:00~0~0~0~1~342.00~341.00~0~0~0~0~0";\n
        """
        let quotes = DataService.parseTencentResponse(raw)
        XCTAssertEqual(quotes.count, 1)
        let q = try XCTUnwrap(quotes["hk00700"])
        XCTAssertEqual(q.price, 342.00, accuracy: 0.001)
        // change = 342.00 - 345.00 = -3.00
        XCTAssertEqual(q.change, -3.00, accuracy: 0.001)
    }

    func test_parseTencent_empty() {
        XCTAssertTrue(DataService.parseTencentResponse("").isEmpty)
    }

    // MARK: - 新浪 suggest（搜索兜底，2026-11-12 实测格式）

    func test_parseSinaSuggest_realFormat() {
        let body = "var suggestvalue=\"AAPL,103,aapl,aapl,AAPL,,AAPL,99,1,,,,;AAPL,41,aapl,aapl,苹果,,苹果,99,1,ESG,,,;"
            + "安培龙,11,301413,sz301413,安培龙,,安培龙,99,1,,,,;00700,31,00700,00700,腾讯控股,,腾讯控股,99,1,ESG,,,\";"
        let results = DataService.parseSinaSuggest(body)
        XCTAssertEqual(results, [
            SearchResult(id: "usr_aapl", name: "苹果", market: .usStock),
            SearchResult(id: "sz301413", name: "安培龙", market: .aStock),
            SearchResult(id: "hk00700", name: "腾讯控股", market: .hkStock),
        ])
    }

    func test_parseSinaSuggest_skipsOtherTypesAndBadAStockCodes() {
        // 103 = 伦敦股、87 = 期货、21 = 基金；类型 11 但完整代码不是 sh/sz/bj 的也跳过
        let body = "var suggestvalue=\"碳酸锂,87,lc0,lc0,碳酸锂,,碳酸锂,99,1,,,,;国融稳康债券,21,007002,of007002,国融稳康债券,,,99,1,,,,;"
            + "怪数据,11,123,xx123,怪数据,,,99,1,,,,;浦发银行,11,600000,sh600000,浦发银行,,浦发银行,99,1,ESG,,,\";"
        XCTAssertEqual(DataService.parseSinaSuggest(body).map(\.id), ["sh600000"])
    }

    func test_parseSinaSuggest_empty() {
        XCTAssertTrue(DataService.parseSinaSuggest("var suggestvalue=\"\";").isEmpty)
        XCTAssertTrue(DataService.parseSinaSuggest("").isEmpty)
    }

    func test_sinaSuggestURL_onlyStockTypes() {
        XCTAssertEqual(DataService.sinaSuggestURL("aapl")?.absoluteString,
                       "https://suggest3.sinajs.cn/suggest/type=11,31,41&key=aapl")
    }
}
