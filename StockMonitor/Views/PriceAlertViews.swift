import SwiftUI
import UserNotifications

/// 编辑页里的到价提醒控件：开关、目标价、方向提示、权限警告。
/// 输入状态由 SettingsView 持有，点「保存」时和成本 / 股数一起提交
@MainActor
struct PriceAlertEditor: View {
    let stock: Stock
    @Binding var targetText: String
    @Binding var isEnabled: Bool
    @EnvironmentObject var appState: AppState
    @ObservedObject private var notifications = NotificationService.shared

    private var targetIsValid: Bool { PriceAlert.parseTarget(targetText) != nil }
    private var targetIsEmpty: Bool { targetText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("到价提醒", isOn: $isEnabled)
                .disabled(!targetIsValid)
            HStack {
                Text("目标价")
                TextField("如 9.50", text: $targetText).textFieldStyle(.roundedBorder).frame(width: 100)
            }
            if !targetIsEmpty && !targetIsValid {
                Text("请输入有效的目标价").font(.caption).foregroundColor(.red)
            } else if isEnabled, let hint = hintText {
                Text(hint).font(.caption).foregroundColor(.secondary)
            }
            if notifications.status == .denied {
                HStack(spacing: 6) {
                    Text("⚠️ 通知未开启").font(.caption)
                    Button("打开系统设置") { notifications.openSystemSettings() }
                        .controlSize(.small)
                }
            }
        }
        .onChange(of: targetText) { _ in
            // 目标价无效时开关视为关闭
            if !targetIsValid { isEnabled = false }
        }
        .task { await notifications.refreshStatus() }
    }

    /// 保存后真正生效的方向（和 AppState.saveEdit 同一套规则）
    private var hintText: String? {
        guard let alert = appState.editedAlert(for: stock, targetText: targetText, isEnabled: true) else { return nil }
        guard alert.direction != nil else { return "暂无可用价格，拿到价格后自动判断涨到还是跌到" }
        let pricePart = appState.quotes[stock.id]
            .flatMap { AppState.alertPrice(for: stock, quote: $0, now: Date()) }
            .map { "现价 \(Quote.format($0.price))，" } ?? ""
        return "\(pricePart)\(alert.summary) 时提醒"
    }
}
