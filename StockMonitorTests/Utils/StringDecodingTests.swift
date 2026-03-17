import XCTest
@testable import StockMonitor

final class StringDecodingTests: XCTestCase {

    func test_decodeGBK_ascii() {
        let data = "hello world".data(using: .ascii)!
        XCTAssertEqual(StringDecoding.decodeGBK(data), "hello world")
    }

    func test_decodeGBK_emptyData() {
        XCTAssertEqual(StringDecoding.decodeGBK(Data()), "")
    }

    func test_decodeGBK_chineseString() {
        // 用 GB18030 编码"平安银行"，再解码，应还原原始字符串
        guard let encoding = String.Encoding.gb18030,
              let data = "平安银行".data(using: encoding) else {
            XCTFail("GB18030 encoding unavailable on this platform")
            return
        }
        XCTAssertEqual(StringDecoding.decodeGBK(data), "平安银行")
    }

    func test_decodeGBK_fallbackToUTF8() {
        // 纯 ASCII/UTF-8 内容也能正常解码
        let data = "AAPL,189.5".data(using: .utf8)!
        XCTAssertEqual(StringDecoding.decodeGBK(data), "AAPL,189.5")
    }
}
