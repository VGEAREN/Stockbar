import AppKit
import Combine
import UserNotifications

/// 到价通知的发送方。AppState 只依赖这个接口，测试里换成假实现
@MainActor
protocol PriceAlertNotifier: AnyObject {
    /// 当前是否有通知权限
    func isAuthorized() async -> Bool
    /// 发一条到价通知
    func notifyPriceReached(_ hit: PriceAlertHit)
}

/// macOS 系统通知（UNUserNotificationCenter）。
/// 只有完整 ad-hoc 签名、且位于「应用程序」目录的 Stockbar.app 才申请得到权限（见设计稿第 1 节）
@MainActor
final class NotificationService: NSObject, ObservableObject, PriceAlertNotifier {
    static let shared = NotificationService()

    /// 当前通知权限，供设置页 / 编辑页显示
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    private var center: UNUserNotificationCenter { .current() }

    /// App 启动时调用：设置代理，让下拉面板打开（App 在前台）时也照常弹横幅
    func activate() {
        center.delegate = self
    }

    /// .authorized / .provisional 视为有权限
    nonisolated static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    func isAuthorized() async -> Bool {
        await refreshStatus()
        return Self.isAllowed(status)
    }

    /// 只在还没决定过时弹系统授权请求；返回最终是否有权限
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshStatus()
        if status == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logToFile("NotificationService: requestAuthorization failed: \(error)")
            }
            await refreshStatus()
        }
        return Self.isAllowed(status)
    }

    func notifyPriceReached(_ hit: PriceAlertHit) {
        post(id: "price-alert.\(hit.stockId).\(Int(Date().timeIntervalSince1970))",
             title: hit.title, body: hit.body)
    }

    /// 设置页「发送测试通知 / 授权并测试」
    func sendTestNotification() async {
        guard await requestAuthorizationIfNeeded() else { return }
        post(id: "test.\(UUID().uuidString)", title: "Stockbar 测试通知", body: "到价提醒会以这种方式通知你")
    }

    /// 打开 系统设置 → 通知 → Stockbar
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.vgearen.Stockbar"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "price-alert"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
            } catch {
                logToFile("NotificationService: add \(id) failed: \(error)")
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// 面板打开时 App 在前台，系统默认不弹横幅；这里要求照常弹出
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
