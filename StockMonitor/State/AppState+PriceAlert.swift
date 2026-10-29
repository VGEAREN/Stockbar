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

    /// 到价判断用的价格；返回 nil 表示这一次不判断（A股集合竞价、美股夜盘拿不到夜盘价、价格无效）。
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
            } else if session == "夜盘" {
                // 夜盘没拿到本时段成交（请求失败 / 还没成交 / 不支持夜盘）：quote.price 是过时的正盘收盘价，这次不判断
                return nil
            }
        }
        guard price > 0 else { return nil }
        return (price, label)
    }

    /// 刷新后检查到价提醒：到价 → 关闭开关并保存 → 发通知（只提醒一次）
    func checkPriceAlerts(now: Date = Date()) async {
        guard stocks.contains(where: { $0.alert?.isEnabled == true }) else { return }
        // 方向未定的先用当前价格定下来：定方向不需要通知权限，免得授权晚了再定、方向和布防时的意图相反
        resolvePendingDirections(now: now)
        // 没有通知权限时先不触发，开关保持开启，授权后再提醒
        guard await notifier.isAuthorized() else { return }

        var updated = stocks
        var hits: [PriceAlertHit] = []
        for i in updated.indices {
            guard var alert = updated[i].alert, alert.isEnabled, let direction = alert.direction,
                  let quote = quotes[updated[i].id],
                  let current = Self.alertPrice(for: updated[i], quote: quote, now: now),
                  alert.isReached(by: current.price) else { continue }
            alert.isEnabled = false
            hits.append(PriceAlertHit(stockId: updated[i].id, stockName: updated[i].name,
                                      price: current.price, targetPrice: alert.targetPrice,
                                      direction: direction, sessionLabel: current.sessionLabel))
            updated[i].alert = alert
        }
        // 先保存再发通知：即使发通知时退出，重启后也不会重复提醒
        if updated != stocks { stocks = updated }
        for hit in hits { notifier.notifyPriceReached(hit) }
    }

    /// 给开启中、方向未定、且已有可用价格的提醒定方向并保存
    private func resolvePendingDirections(now: Date) {
        var updated = stocks
        for i in updated.indices {
            guard var alert = updated[i].alert, alert.isEnabled, alert.direction == nil,
                  let quote = quotes[updated[i].id],
                  let current = Self.alertPrice(for: updated[i], quote: quote, now: now) else { continue }
            alert.direction = PriceAlert.direction(target: alert.targetPrice, currentPrice: current.price)
            updated[i].alert = alert
        }
        if updated != stocks { stocks = updated }
    }

    // MARK: - 编辑页

    /// 编辑页保存时算出新的提醒；目标价为空或无效时返回 nil（= 删除提醒）
    func editedAlert(for stock: Stock, targetText: String, isEnabled: Bool, now: Date = Date()) -> PriceAlert? {
        guard let target = PriceAlert.parseTarget(targetText) else { return nil }
        let current = quotes[stock.id].flatMap { Self.alertPrice(for: stock, quote: $0, now: now)?.price }
        return PriceAlert.edited(previous: stock.alert, targetPrice: target,
                                 isEnabled: isEnabled, currentPrice: current)
    }

    /// 编辑页「保存」：成本 / 股数写当前观察仓或真实持仓；提醒始终写在股票本身（不分观察仓）。
    /// 返回保存后的提醒，界面据此决定是否申请通知权限
    @discardableResult
    func saveEdit(stockId: String, cost: Double?, shares: Double?,
                  alertTargetText: String, alertEnabled: Bool, now: Date = Date()) -> PriceAlert? {
        // 成本 / 股数必须是有限数：Double("inf") / Double("nan") 能解析成功，但 JSONEncoder 编码会抛错，之后的保存会全部失败
        let cost   = cost.flatMap   { $0.isFinite ? $0 : nil }
        let shares = shares.flatMap { $0.isFinite ? $0 : nil }
        guard let idx = stocks.firstIndex(where: { $0.id == stockId }) else { return nil }
        var updated = stocks
        let alert = editedAlert(for: updated[idx], targetText: alertTargetText,
                                isEnabled: alertEnabled, now: now)
        if let wlId = config.activeWatchlistId,
           let wlIdx = watchlists.firstIndex(where: { $0.id == wlId }) {
            // 写入观察仓
            if let c = cost, let s = shares {
                watchlists[wlIdx].entries[stockId] = WatchlistEntry(costPrice: c, holdingShares: s)
            } else {
                watchlists[wlIdx].entries.removeValue(forKey: stockId)
            }
        } else {
            // 写入真实持仓
            updated[idx].costPrice     = cost
            updated[idx].holdingShares = shares
        }
        updated[idx].alert = alert
        // 成本 / 股数和提醒合并成一次赋值：只保存、备份一次；没变化就不写
        if updated != stocks { stocks = updated }
        return alert
    }
}
