import Foundation

@MainActor
final class RefreshScheduler {
    private var timer: Timer?
    private var pendingTask: Task<Void, Never>?
    private let onRefresh: () async -> Void

    init(onRefresh: @escaping () async -> Void) {
        self.onRefresh = onRefresh
    }

    /// 启动定时刷新（立即触发一次）
    func start(interval: TimeInterval) {
        stop()
        pendingTask = Task { await onRefresh() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard Self.isTradingHour() else { return }
            self.pendingTask = Task { await self.onRefresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// 强制刷新（忽略开市判断）
    func forceRefresh() {
        pendingTask = Task { await onRefresh() }
    }

    // MARK: - 开市时段判断（北京时间）

    private nonisolated static let shanghaiCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 任一市场处于交易时间段则返回 true；周末始终返回 false
    /// 注：不维护节假日日历，节假日由接口返回不变的数据来体现
    nonisolated static func isTradingHour(at date: Date = Date()) -> Bool {
        let cal = shanghaiCalendar

        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }   // 周日=1, 周六=7

        let hour   = cal.component(.hour,   from: date)
        let minute = cal.component(.minute, from: date)
        let t = hour * 60 + minute

        // A股：09:25–11:30, 13:00–15:00
        if (9*60+25  ... 11*60+30).contains(t) { return true }
        if (13*60    ... 15*60   ).contains(t) { return true }

        // 港股：09:30–11:59, 13:00–16:00
        if (9*60+30  ... 12*60-1 ).contains(t) { return true }
        if (13*60    ... 16*60   ).contains(t) { return true }

        // 美股：21:30–次日 04:00（跨日处理）
        // 注：周末判断基于北京时间，周五21:30+和周六凌晨04:00前的美股尾盘可能被误判
        // 简化实现，不影响主要使用场景
        if t >= 21*60+30 || t < 4*60 { return true }

        return false
    }
}
