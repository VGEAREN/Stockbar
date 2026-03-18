import XCTest
@testable import Stockbar

final class AppSettingsTests: XCTestCase {

    func test_chinese_upIsRed() {
        let s = AppSettings(colorScheme: .chinese, refreshInterval: 5, statusBarStockId: nil)
        XCTAssertEqual(s.upColorName,   "upRed")
        XCTAssertEqual(s.downColorName, "downGreen")
    }

    func test_western_upIsGreen() {
        let s = AppSettings(colorScheme: .western, refreshInterval: 5, statusBarStockId: nil)
        XCTAssertEqual(s.upColorName,   "upGreen")
        XCTAssertEqual(s.downColorName, "downRed")
    }

    func test_validRefreshIntervals() {
        for interval in AppSettings.validRefreshIntervals {
            let s = AppSettings(colorScheme: .chinese, refreshInterval: interval, statusBarStockId: nil)
            XCTAssertEqual(s.refreshInterval, interval)
        }
    }

    func test_colorTheme_allCases() {
        XCTAssertEqual(ColorTheme.allCases.count, 2)
        XCTAssertTrue(ColorTheme.allCases.contains(.chinese))
        XCTAssertTrue(ColorTheme.allCases.contains(.western))
    }
}
