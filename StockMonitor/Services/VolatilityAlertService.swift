import Foundation
import UserNotifications

final class VolatilityAlertService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = VolatilityAlertService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logToFile("VolatilityAlertService: requestAuthorization failed: \(error)")
            return false
        }
    }

    func notify(stockName: String, stockId: String, changePercent: Double, threshold: Double) async {
        guard await requestAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(stockName) 波动提醒"
        let direction = changePercent >= 0 ? "上涨" : "下跌"
        content.body = "当前\(direction) \(String(format: "%.2f%%", abs(changePercent)))，已超过 \(String(format: "%.2f%%", threshold))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "volatility-\(stockId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            logToFile("VolatilityAlertService: add notification failed: \(error)")
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
