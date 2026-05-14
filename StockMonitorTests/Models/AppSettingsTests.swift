import XCTest
@testable import Stockbar

final class AppSettingsTests: XCTestCase {

    func test_chinese_upIsRed() {
        var s = AppSettings()
        s.colorScheme = .chinese
        XCTAssertEqual(s.upColorName,   "upRed")
        XCTAssertEqual(s.downColorName, "downGreen")
    }

    func test_western_upIsGreen() {
        var s = AppSettings()
        s.colorScheme = .western
        XCTAssertEqual(s.upColorName,   "upGreen")
        XCTAssertEqual(s.downColorName, "downRed")
    }

    func test_validRefreshIntervals() {
        for interval in AppSettings.validRefreshIntervals {
            var s = AppSettings()
            s.refreshInterval = interval
            XCTAssertEqual(s.refreshInterval, interval)
        }
    }

    func test_colorTheme_allCases() {
        XCTAssertEqual(ColorTheme.allCases.count, 2)
        XCTAssertTrue(ColorTheme.allCases.contains(.chinese))
        XCTAssertTrue(ColorTheme.allCases.contains(.western))
    }
}
