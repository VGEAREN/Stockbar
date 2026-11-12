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

    /// 收盘后再刷新这么久，好拿到收盘价
    nonisolated static let closeGrace: TimeInterval = 30 * 60

    /// 自动刷新时间窗：任一市场在交易时段，或收盘后 30 分钟内。
    /// 各市场按自己的时间判断，而不是"北京时间工作日"——以前北京时间周六凌晨
    ///（美股周五后半场和盘后）不会自动刷新，周末一直停在美东周五上午的价格
    /// 注：不维护节假日日历，节假日由接口返回不变的数据来体现
    nonisolated static func isTradingHour(at date: Date = Date()) -> Bool {
        isAnyMarketOpen(at: date) || isAnyMarketOpen(at: date.addingTimeInterval(-closeGrace))
    }

    /// 任一市场此刻是否在交易时段
    /// - A股：北京 09:15–11:30、13:00–15:00
    /// - 港股：北京 09:30–12:00、13:00–16:10（含收盘竞价）
    /// - 韩股：KST 09:00–15:30（`AppState.koreanMarketSession`）
    /// - 美股：盘前 / 盘中 / 盘后 / 夜盘（`AppState.usMarketSession`，夜盘只在周日~周四晚）
    nonisolated static func isAnyMarketOpen(at date: Date) -> Bool {
        if AppState.usMarketSession(at: date) != nil { return true }
        if AppState.koreanMarketSession(at: date) != nil { return true }

        let cal = shanghaiCalendar
        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }   // 周日=1, 周六=7

        let t = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        if (9*60+15 ... 11*60+30).contains(t) || (13*60 ... 15*60).contains(t)    { return true }  // A股
        if (9*60+30 ... 12*60).contains(t)    || (13*60 ... 16*60+10).contains(t) { return true }  // 港股
        return false
    }
}
