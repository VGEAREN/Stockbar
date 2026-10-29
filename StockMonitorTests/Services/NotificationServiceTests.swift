import XCTest
import UserNotifications
@testable import Stockbar

final class NotificationServiceTests: XCTestCase {

    func test_isAllowed_onlyForAuthorizedOrProvisional() {
        XCTAssertTrue(NotificationService.isAllowed(.authorized))
        XCTAssertTrue(NotificationService.isAllowed(.provisional))
        XCTAssertFalse(NotificationService.isAllowed(.denied))
        XCTAssertFalse(NotificationService.isAllowed(.notDetermined))
    }
}
