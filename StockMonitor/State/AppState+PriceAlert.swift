import Foundation

// MARK: - 到价提醒

extension AppState {

    /// A股集合竞价时段（北京时间周一至周五 09:15–09:25）。这段时间是虚拟撮合价，会随撤单跳动，
    /// 既不用来判断到价，也不用来定方向
    nonisolated static func isAStockCallAuction(at now: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: now)
        // Swift Calendar weekday: 1=周日, 2=周一, ..., 6=周五, 7=周六
        let wd = comps.weekday ?? 1
        guard wd >= 2 && wd <= 6 else { return false }
        let t = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return t >= 9 * 60 + 15 && t < 9 * 60 + 25
    }

    /// 到价判断用的价格；返回 nil 表示这一次不判断（A股集合竞价、价格无效）。
    /// 美股不在盘中时，有时段价（盘前 / 盘后 / 夜盘价）就用时段价并带上时段名；休市时记为「盘后」
    nonisolated static func alertPrice(for stock: Stock, quote: Quote, now: Date) -> (price: Double, sessionLabel: String?)? {
        if stock.market == .aStock && isAStockCallAuction(at: now) { return nil }
        var price = quote.price
        var label: String? = nil
        if stock.market == .usStock {
            let session = usMarketSession(at: now)
            if session != "盘中", let ext = quote.extendedPrice, ext > 0 {
                price = ext
                label = session ?? "盘后"
            }
        }
        guard price > 0 else { return nil }
        return (price, label)
    }

    /// 刷新后检查到价提醒：到价 → 关闭开关并保存 → 发通知（只提醒一次）
    func checkPriceAlerts(now: Date = Date()) async {
        guard stocks.contains(where: { $0.alert?.isEnabled == true }) else { return }
        // 没有通知权限时先不触发，开关保持开启，授权后再提醒
        guard await notifier.isAuthorized() else { return }

        var updated = stocks
        var hits: [PriceAlertHit] = []
        for i in updated.indices {
            guard var alert = updated[i].alert, alert.isEnabled,
                  let quote = quotes[updated[i].id],
                  let current = Self.alertPrice(for: updated[i], quote: quote, now: now) else { continue }
            if alert.direction == nil {
                alert.direction = PriceAlert.direction(target: alert.targetPrice, currentPrice: current.price)
            }
            if alert.isReached(by: current.price), let direction = alert.direction {
                alert.isEnabled = false
                hits.append(PriceAlertHit(stockId: updated[i].id, stockName: updated[i].name,
                                          price: current.price, targetPrice: alert.targetPrice,
                                          direction: direction, sessionLabel: current.sessionLabel))
            }
            updated[i].alert = alert
        }
        // 先保存再发通知：即使发通知时退出，重启后也不会重复提醒
        if updated != stocks { stocks = updated }
        for hit in hits { notifier.notifyPriceReached(hit) }
    }
}
