# 到价提醒 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每只股票可设一个目标价，涨到 / 跌到时发一次 macOS 系统通知，发完自动关闭这只股票的提醒开关。

**Architecture:** 提醒（`PriceAlert`：目标价 + 自动判断的方向 + 开关）挂在 `Stock` 上随 stocks.json 持久化；`AppState.refresh()` 合并行情后调 `checkPriceAlerts()`，判断规则全部是可单测的纯函数；通知经 `PriceAlertNotifier` 接口由 `NotificationService`（`UNUserNotificationCenter`）发出，测试注入假实现。发布包补完整 ad-hoc 签名，否则系统拒绝通知权限。

**Tech Stack:** Swift 5（语言模式）/ SwiftUI / UserNotifications / XCTest，Xcode 27.1。

**Spec:** `docs/superpowers/specs/2026-10-29-price-alert-design.md`

## Global Constraints

- 部署目标 macOS 13.5（`MACOSX_DEPLOYMENT_TARGET = 13.5`）：不用更新的 API；`onChange` 用单参数闭包写法 `.onChange(of: x) { _ in … }`（同现有代码）
- 语言模式 Swift 5（`SWIFT_VERSION = 5.0`）
- `StockMonitor/`、`StockMonitorTests/` 下新建的文件会被 Xcode 自动纳入（`PBXFileSystemSynchronizedRootGroup`），**不要改 `project.pbxproj`**
- 模块名 `Stockbar`（`@testable import Stockbar`），测试 target `StockbarTests`，Bundle ID `com.vgearen.Stockbar`
- 通知标题 `<股票名> 到价提醒`；正文 `<现价|盘前|盘后|夜盘> <价格>，已<涨到|跌到>目标价 <目标价>`；价格一律用 `Quote.format`（≥ 10 两位小数，否则三位）
- 构造 `AppState` 的测试必须在 `setUp` 里把 `AppState.appSupportDirOverride` 指向新建的临时目录，`tearDown` 里清掉（同 `AppStateTests`）
- `Stock` 新字段解码一律 `try? c.decodeIfPresent(…)`，坏字段不能让整个 `[Stock]` 解码失败
- 注释用中文，风格同现有代码（`// MARK: -` 分节）
- 在分支 `feat/price-alert` 上工作，每个任务结束提交一次，**不推送**；提交信息末尾加 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
- `CLAUDE.md` 被 gitignore：只在本地改，**不要** `git add -f`
- **不要在已安装的 Stockbar 运行时启动自己编出来的 Stockbar**（两个进程会同时写 `~/Library/Application Support/Stockbar/stocks.json`）。真机运行只在 Task 9、经用户同意后进行

**测试命令**（在 `StockMonitor/StockMonitor/` 下执行，即含 `StockMonitor.xcodeproj` 的目录）：

```bash
# 单个测试类：把 <TestClass> 换成类名；去掉 -only-testing 那一行即跑全部
xcodebuild test -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/stockbar_test_dd \
  -only-testing:StockbarTests/<TestClass> \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "\.swift:[0-9]+:[0-9]+: error:|Test case .*(passed|failed)|TEST (SUCCEEDED|FAILED)"
```

输出里每条测试是 `Test case 'PriceAlertTests.test_xxx()' passed on 'My Mac - Stockbar (…)'`。xcodebuild 会打印一堆 `DVTPlugIn` / `CoreSimulator is out of date` 的报错，那是 Xcode 插件版本问题，与本项目无关，上面的过滤已去掉它们。改动前基准：全部测试通过（`** TEST SUCCEEDED **`，约 20 秒）。

---

## File Structure

**新文件**

| 文件 | 职责 |
|------|------|
| `StockMonitor/Models/PriceAlert.swift` | `PriceAlert`（数据 + 方向 / 到价 / 编辑规则 + 界面短文案）、`PriceAlertHit`（一次到价 + 通知文案） |
| `StockMonitor/Services/NotificationService.swift` | `PriceAlertNotifier` 接口；`NotificationService`：权限、发通知、前台横幅代理、打开系统设置 |
| `StockMonitor/State/AppState+PriceAlert.swift` | `AppState` 扩展：判断用价格、A股竞价时段、`checkPriceAlerts`、编辑页 `editedAlert` / `saveEdit` |
| `StockMonitor/Views/PriceAlertViews.swift` | `PriceAlertEditor`（编辑页提醒控件）、`PriceAlertPermissionRow`（设置页权限行） |
| `StockMonitorTests/Models/PriceAlertTests.swift` | 纯规则与文案 |
| `StockMonitorTests/Services/NotificationServiceTests.swift` | 权限状态映射 |
| `StockMonitorTests/State/PriceAlertCheckTests.swift` | 到价检查（假 notifier + 临时目录） |
| `StockMonitorTests/State/AppStateEditTests.swift` | 编辑页保存 |

**修改**

| 文件 | 改动 |
|------|------|
| `StockMonitor/Models/Quote.swift` | 抽出 `static func format(_:)` |
| `StockMonitor/Models/Stock.swift` | `alert` 字段 + 容错解码 |
| `StockMonitor/State/AppState.swift` | 测试时不启动自动刷新；`notifier` 属性；`refresh()` 末尾调检查 |
| `StockMonitor/StockMonitorApp.swift` | 启动时 `NotificationService.shared.activate()` |
| `StockMonitor/Views/SettingsView.swift` | 编辑页接入提醒控件与 `saveEdit`；「我的股票」提醒行；「到价提醒」分组 |
| `StockMonitor/Views/StockRowView.swift` | 代码行后加铃铛角标 |
| `.github/workflows/release.yml` | 打 DMG 前补 ad-hoc 签名并校验 |
| `README.md`、`README_CN.md` | 功能列表 + 「到价提醒」使用说明 |
| `StockMonitorTests/Models/QuoteTests.swift`、`StockTests.swift`、`State/AppStateTests.swift` | 追加测试 |
| （本地，不提交）`CLAUDE.md`、打包备忘 | 结构、签名步骤、踩坑记录 |

---

### Task 1: PriceAlert 模型与判断规则

**Files:**
- Create: `StockMonitor/Models/PriceAlert.swift`
- Modify: `StockMonitor/Models/Quote.swift`（`formattedExtendedPrice`、`formattedPrice`）
- Test: `StockMonitorTests/Models/PriceAlertTests.swift`（新）、`StockMonitorTests/Models/QuoteTests.swift`（追加）

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct PriceAlert: Codable, Equatable { enum Direction: String, Codable { case rise, fall }; var targetPrice: Double; var direction: Direction?; var isEnabled: Bool }`
  - `static func PriceAlert.direction(target: Double, currentPrice: Double) -> PriceAlert.Direction`
  - `func PriceAlert.isReached(by price: Double) -> Bool`
  - `static func PriceAlert.parseTarget(_ text: String) -> Double?`
  - `static func PriceAlert.edited(previous: PriceAlert?, targetPrice: Double, isEnabled: Bool, currentPrice: Double?) -> PriceAlert`
  - `var PriceAlert.summary: String`（`涨到 X` / `跌到 X` / `目标 X`）、`var PriceAlert.badge: String`（`↑X` / `↓X` / `X`）
  - `struct PriceAlertHit: Equatable { let stockId: String; let stockName: String; let price: Double; let targetPrice: Double; let direction: PriceAlert.Direction; let sessionLabel: String?; var title: String; var body: String }`
  - `static func Quote.format(_ price: Double) -> String`

- [ ] **Step 1: 写失败的测试**

新建 `StockMonitorTests/Models/PriceAlertTests.swift`：

```swift
import XCTest
@testable import Stockbar

final class PriceAlertTests: XCTestCase {

    // MARK: - 方向

    func test_direction_targetAbovePrice_isRise() {
        XCTAssertEqual(PriceAlert.direction(target: 11, currentPrice: 10), .rise)
    }

    func test_direction_targetBelowPrice_isFall() {
        XCTAssertEqual(PriceAlert.direction(target: 9, currentPrice: 10), .fall)
    }

    func test_direction_targetEqualsPrice_isRise() {
        XCTAssertEqual(PriceAlert.direction(target: 10, currentPrice: 10), .rise)
    }

    // MARK: - 到价

    func test_isReached_rise_boundary() {
        let a = PriceAlert(targetPrice: 11, direction: .rise, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 10.99))
        XCTAssertTrue(a.isReached(by: 11))
        XCTAssertTrue(a.isReached(by: 11.5))
    }

    func test_isReached_fall_boundary() {
        let a = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 9.01))
        XCTAssertTrue(a.isReached(by: 9))
        XCTAssertTrue(a.isReached(by: 8.5))
    }

    func test_isReached_falseWhenDisabled() {
        let a = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: false)
        XCTAssertFalse(a.isReached(by: 8))
    }

    func test_isReached_falseWhenDirectionUnknown() {
        let a = PriceAlert(targetPrice: 9, direction: nil, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 8))
    }

    func test_isReached_falseForNonPositivePrice() {
        let a = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        XCTAssertFalse(a.isReached(by: 0))
        XCTAssertFalse(a.isReached(by: -1))
    }

    // MARK: - 目标价输入

    func test_parseTarget() {
        XCTAssertEqual(PriceAlert.parseTarget("9.5"), 9.5)
        XCTAssertEqual(PriceAlert.parseTarget(" 12 "), 12)
        XCTAssertNil(PriceAlert.parseTarget(""))
        XCTAssertNil(PriceAlert.parseTarget("abc"))
        XCTAssertNil(PriceAlert.parseTarget("9.5."))
        XCTAssertNil(PriceAlert.parseTarget("0"))
        XCTAssertNil(PriceAlert.parseTarget("-3"))
        XCTAssertNil(PriceAlert.parseTarget("inf"))
    }

    // MARK: - 编辑页保存规则

    func test_edited_newEnabled_setsDirectionFromPrice() {
        let a = PriceAlert.edited(previous: nil, targetPrice: 9, isEnabled: true, currentPrice: 10)
        XCTAssertEqual(a, PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true))
    }

    func test_edited_newWithoutPrice_leavesDirectionNil() {
        let a = PriceAlert.edited(previous: nil, targetPrice: 9, isEnabled: true, currentPrice: nil)
        XCTAssertEqual(a, PriceAlert(targetPrice: 9, direction: nil, isEnabled: true))
    }

    func test_edited_reEnable_recomputesDirection() {
        // 触发后开关已关；现价 8 低于目标 9，再打开时这次应等"涨到"
        let fired = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: false)
        let a = PriceAlert.edited(previous: fired, targetPrice: 9, isEnabled: true, currentPrice: 8)
        XCTAssertEqual(a.direction, .rise)
    }

    func test_edited_changedTarget_recomputesDirection() {
        let prev = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        let a = PriceAlert.edited(previous: prev, targetPrice: 12, isEnabled: true, currentPrice: 10)
        XCTAssertEqual(a.direction, .rise)
    }

    func test_edited_unchangedEnabledAlert_keepsDirection() {
        // 价格已越过目标价（9.4 < 9.5，还没触发），只改成本价保存时方向不能翻成"涨到"
        let prev = PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true)
        let a = PriceAlert.edited(previous: prev, targetPrice: 9.5, isEnabled: true, currentPrice: 9.4)
        XCTAssertEqual(a.direction, .fall)
    }

    func test_edited_disabled_keepsPreviousDirection() {
        let prev = PriceAlert(targetPrice: 9, direction: .fall, isEnabled: true)
        let a = PriceAlert.edited(previous: prev, targetPrice: 9, isEnabled: false, currentPrice: 10)
        XCTAssertEqual(a, PriceAlert(targetPrice: 9, direction: .fall, isEnabled: false))
    }

    // MARK: - 文案

    func test_hit_title_and_body_fall() {
        let hit = PriceAlertHit(stockId: "sh600000", stockName: "浦发银行", price: 9.48,
                                targetPrice: 9.5, direction: .fall, sessionLabel: nil)
        XCTAssertEqual(hit.title, "浦发银行 到价提醒")
        XCTAssertEqual(hit.body, "现价 9.480，已跌到目标价 9.500")
    }

    func test_hit_body_usExtendedSession() {
        let hit = PriceAlertHit(stockId: "usr_aapl", stockName: "苹果", price: 182.3,
                                targetPrice: 182, direction: .rise, sessionLabel: "盘后")
        XCTAssertEqual(hit.body, "盘后 182.30，已涨到目标价 182.00")
    }

    func test_summary() {
        XCTAssertEqual(PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true).summary, "跌到 9.500")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: .rise, isEnabled: true).summary, "涨到 11.00")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: nil, isEnabled: true).summary, "目标 11.00")
    }

    func test_badge() {
        XCTAssertEqual(PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true).badge, "↓9.500")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: .rise, isEnabled: true).badge, "↑11.00")
        XCTAssertEqual(PriceAlert(targetPrice: 11, direction: nil, isEnabled: true).badge, "11.00")
    }
}
```

在 `StockMonitorTests/Models/QuoteTests.swift` 末尾的 `}` 之前追加：

```swift
    func test_format_sharedRule() {
        XCTAssertEqual(Quote.format(1688), "1688.00")
        XCTAssertEqual(Quote.format(10), "10.00")
        XCTAssertEqual(Quote.format(9.5), "9.500")
    }

    func test_formattedExtendedPrice_usesSameRule() {
        var q = Quote(code: "usr_aapl", price: 180, change: 0, changePercent: 0, updateTime: "")
        XCTAssertNil(q.formattedExtendedPrice)
        q.extendedPrice = 9.5
        XCTAssertEqual(q.formattedExtendedPrice, "9.500")
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: 测试命令，`-only-testing:StockbarTests/PriceAlertTests -only-testing:StockbarTests/QuoteTests`
Expected: 编译失败，出现 `error: cannot find 'PriceAlert' in scope`、`error: type 'Quote' has no member 'format'`，`** TEST FAILED **`

- [ ] **Step 3: 实现**

新建 `StockMonitor/Models/PriceAlert.swift`：

```swift
import Foundation

/// 到价提醒：每只股票一个目标价。方向（涨到 / 跌到）在布防时按当时价格自动判断，
/// 到价后只通知一次并自动关闭开关
struct PriceAlert: Codable, Equatable {
    enum Direction: String, Codable {
        case rise   // 涨到
        case fall   // 跌到
    }

    var targetPrice: Double
    var direction: Direction?   // nil = 布防时还没有可用价格，首次拿到价格时再定
    var isEnabled: Bool         // 这只股票的提醒开关

    /// 目标价 ≥ 现价 → 等涨到；否则 → 等跌到
    static func direction(target: Double, currentPrice: Double) -> Direction {
        target >= currentPrice ? .rise : .fall
    }

    /// 是否到价：开关开启、方向已定、价格有效时，涨到 = 价格 ≥ 目标价，跌到 = 价格 ≤ 目标价
    func isReached(by price: Double) -> Bool {
        guard isEnabled, price > 0, let direction else { return false }
        switch direction {
        case .rise: return price >= targetPrice
        case .fall: return price <= targetPrice
        }
    }

    /// 解析编辑页输入的目标价：去掉首尾空白后必须是有限正数，否则返回 nil
    static func parseTarget(_ text: String) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// 编辑页保存时生成新的提醒。
    /// - 重新布防（新建并开启 / 开关从关到开 / 开启状态下改了目标价）→ 用当前价格重新定方向；没有价格先留空
    /// - 其它情况（开关一直开着、目标价没变）→ 保持原方向，避免价格已越过目标价时把方向弄反
    static func edited(previous: PriceAlert?, targetPrice: Double, isEnabled: Bool,
                       currentPrice: Double?) -> PriceAlert {
        let staysArmed = previous?.isEnabled == true && previous?.targetPrice == targetPrice
        let direction: Direction?
        if isEnabled && !staysArmed {
            direction = currentPrice.flatMap { $0 > 0 ? Self.direction(target: targetPrice, currentPrice: $0) : nil }
        } else {
            direction = previous?.direction
        }
        return PriceAlert(targetPrice: targetPrice, direction: direction, isEnabled: isEnabled)
    }

    /// 界面上的简短描述："涨到 11.00" / "跌到 9.500"；方向未定时 "目标 9.500"
    var summary: String {
        let target = Quote.format(targetPrice)
        switch direction {
        case .rise?: return "涨到 \(target)"
        case .fall?: return "跌到 \(target)"
        case nil:    return "目标 \(target)"
        }
    }

    /// 主列表角标："↑11.00" / "↓9.500"；方向未定时只显示目标价
    var badge: String {
        let target = Quote.format(targetPrice)
        switch direction {
        case .rise?: return "↑\(target)"
        case .fall?: return "↓\(target)"
        case nil:    return target
        }
    }
}

/// 一次到价：拼通知文案所需的全部信息
struct PriceAlertHit: Equatable {
    let stockId: String
    let stockName: String
    let price: Double
    let targetPrice: Double
    let direction: PriceAlert.Direction
    let sessionLabel: String?   // 美股用时段价时为 "盘前" / "盘后" / "夜盘"

    var title: String { "\(stockName) 到价提醒" }

    var body: String {
        let verb = direction == .rise ? "涨到" : "跌到"
        return "\(sessionLabel ?? "现价") \(Quote.format(price))，已\(verb)目标价 \(Quote.format(targetPrice))"
    }
}
```

在 `StockMonitor/Models/Quote.swift` 中，把

```swift
    var formattedExtendedPrice: String? {
        guard let p = extendedPrice else { return nil }
        if p >= 10 { return String(format: "%.2f", p) }
        return String(format: "%.3f", p)
    }
```

替换为

```swift
    var formattedExtendedPrice: String? {
        extendedPrice.map(Self.format)
    }
```

把

```swift
    var formattedPrice: String {
        if price >= 10 { return String(format: "%.2f", price) }
        return String(format: "%.3f", price)
    }
```

替换为

```swift
    var formattedPrice: String { Self.format(price) }

    /// 价格显示规则：≥ 10 保留两位小数，否则三位（列表、到价提醒共用）
    static func format(_ price: Double) -> String {
        price >= 10 ? String(format: "%.2f", price) : String(format: "%.3f", price)
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: 同 Step 2
Expected: `PriceAlertTests` 全部 `passed`（19 条），`QuoteTests` 全部 `passed`（10 条），`** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add StockMonitor/Models/PriceAlert.swift StockMonitor/Models/Quote.swift \
        StockMonitorTests/Models/PriceAlertTests.swift StockMonitorTests/Models/QuoteTests.swift
git commit -F - <<'EOF'
feat(price-alert): add PriceAlert model and trigger rules

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Stock 持久化提醒（容错解码）

**Files:**
- Modify: `StockMonitor/Models/Stock.swift`
- Test: `StockMonitorTests/Models/StockTests.swift`（追加）

**Interfaces:**
- Consumes: `PriceAlert`（Task 1）
- Produces: `Stock.alert: PriceAlert?`，默认 `nil`；成员初始化器多一个末尾参数 `alert:`（有默认值，现有调用不用改）

- [ ] **Step 1: 写失败的测试**

在 `StockMonitorTests/Models/StockTests.swift` 末尾的 `}` 之前追加：

```swift
    // MARK: - 到价提醒持久化

    func test_stock_decodesLegacyJSONWithoutAlert() throws {
        let json = #"{"id":"sh600000","name":"浦发银行","market":"A股","costPrice":8.5,"holdingShares":1000}"#
        let s = try JSONDecoder().decode(Stock.self, from: Data(json.utf8))
        XCTAssertNil(s.alert)
        XCTAssertEqual(s.costPrice, 8.5)
    }

    func test_stock_codable_roundtrip_withAlert() throws {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock, costPrice: nil, holdingShares: nil,
                          alert: PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))
        let decoded = try JSONDecoder().decode(Stock.self, from: JSONEncoder().encode(stock))
        XCTAssertEqual(decoded, stock)
    }

    func test_stock_corruptAlert_keepsOtherFields() throws {
        let json = #"{"id":"sh600000","name":"浦发银行","market":"A股","holdingShares":1000,"alert":{"targetPrice":"oops"}}"#
        let s = try JSONDecoder().decode(Stock.self, from: Data(json.utf8))
        XCTAssertNil(s.alert)
        XCTAssertEqual(s.holdingShares, 1000)
    }

    func test_stockList_oneCorruptAlert_doesNotEmptyTheList() throws {
        let json = #"[{"id":"sh600000","name":"A","market":"A股","alert":{"targetPrice":"oops"}},{"id":"hk00700","name":"B","market":"港股"}]"#
        let list = try JSONDecoder().decode([Stock].self, from: Data(json.utf8))
        XCTAssertEqual(list.map(\.id), ["sh600000", "hk00700"])
    }

    func test_stock_withoutAlert_doesNotWriteAlertKey() throws {
        let stock = Stock(id: "sh600000", name: "浦发银行", market: .aStock, costPrice: nil, holdingShares: nil)
        let json = String(decoding: try JSONEncoder().encode(stock), as: UTF8.self)
        XCTAssertFalse(json.contains("alert"))
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: 测试命令，`-only-testing:StockbarTests/StockTests`
Expected: 编译失败，`error: extra argument 'alert' in call` / `error: value of type 'Stock' has no member 'alert'`，`** TEST FAILED **`

- [ ] **Step 3: 实现**

`StockMonitor/Models/Stock.swift`，在 `holdingShares` 那行下面加字段：

```swift
    var holdingShares: Double?  // 持仓股数（nil = 未设置）
    var alert: PriceAlert? = nil  // 到价提醒（nil = 未设置）
```

把 Codable 扩展里的

```swift
    enum CodingKeys: String, CodingKey {
        case id, name, market, costPrice, holdingShares
    }
```

改为

```swift
    enum CodingKeys: String, CodingKey {
        case id, name, market, costPrice, holdingShares, alert
    }
```

在 `init(from:)` 的 `holdingShares = …` 那行之后加：

```swift
        // 提醒字段损坏时只丢提醒：loadStocks 里任何一条 Stock 解码失败都会让整个列表读成空
        alert        = try? c.decodeIfPresent(PriceAlert.self, forKey: .alert)
```

（编码沿用编译器合成的 `encode(to:)`，`nil` 时自动不写这个键。）

- [ ] **Step 4: 运行，确认通过**

Run: 测试命令，`-only-testing:StockbarTests/StockTests -only-testing:StockbarTests/PriceAlertTests`
Expected: 全部 `passed`，`** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add StockMonitor/Models/Stock.swift StockMonitorTests/Models/StockTests.swift
git commit -F - <<'EOF'
feat(price-alert): persist alert on Stock with tolerant decoding

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: 单元测试时不启动自动刷新

背景：测试宿主就是 Stockbar.app（`TEST_HOST`）。宿主里的 `AppState` 用真实数据目录并定时刷新，会跑名称同步，之后还会跑到价检查，可能改写用户真实的 stocks.json；测试里自建的 `AppState` 也会在后台联网刷新，和测试手工设置的 `quotes` 互相干扰。

实测（Xcode 27.1）：宿主进程里 `XCTestConfigurationFilePath` **存在但值为空字符串**，`XCTestSessionIdentifier` 有值（UUID）。两者任一存在即视为在跑测试。

**Files:**
- Modify: `StockMonitor/State/AppState.swift`（「刷新调度」一节）
- Test: `StockMonitorTests/State/AppStateTests.swift`（追加）

**Interfaces:**
- Produces: `nonisolated static let AppState.isRunningUnitTests: Bool`；`AppState.scheduler` 改为 `private(set)`（测试可读）

- [ ] **Step 1: 写失败的测试**

在 `StockMonitorTests/State/AppStateTests.swift` 末尾的 `}` 之前追加：

```swift
    func test_unitTests_doNotStartAutoRefresh() {
        // 测试宿主就是 Stockbar.app：自动刷新会拿真实数据跑名称同步 / 到价检查
        XCTAssertTrue(AppState.isRunningUnitTests)
        XCTAssertNil(sut.scheduler)
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: 测试命令，`-only-testing:StockbarTests/AppStateTests`
Expected: 编译失败，`error: type 'AppState' has no member 'isRunningUnitTests'`、`error: 'scheduler' is inaccessible due to 'private' protection level`，`** TEST FAILED **`

- [ ] **Step 3: 实现**

`StockMonitor/State/AppState.swift`，把

```swift
    // MARK: - 刷新调度

    private var scheduler: RefreshScheduler?
```

改为

```swift
    // MARK: - 刷新调度

    private(set) var scheduler: RefreshScheduler?

    /// 是否运行在单元测试里。测试宿主就是 Stockbar.app，宿主里的 AppState 读写真实数据目录；
    /// 测试时不启动自动刷新，避免名称同步 / 到价检查改动用户真实的 stocks.json。
    /// Xcode 27 下 XCTestConfigurationFilePath 存在但值为空，所以同时看 XCTestSessionIdentifier
    nonisolated static let isRunningUnitTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }()
```

把

```swift
    func setupScheduler() {
        scheduler = RefreshScheduler { [weak self] in await self?.refresh() }
```

改为

```swift
    func setupScheduler() {
        guard !Self.isRunningUnitTests else { return }
        scheduler = RefreshScheduler { [weak self] in await self?.refresh() }
```

- [ ] **Step 4: 运行，确认通过**

Run: 测试命令，**不带** `-only-testing`（全部测试）
Expected: 全部 `passed`，`** TEST SUCCEEDED **`（`RefreshSchedulerTests` 直接测调度器，不受影响）

- [ ] **Step 5: 提交**

```bash
git add StockMonitor/State/AppState.swift StockMonitorTests/State/AppStateTests.swift
git commit -F - <<'EOF'
fix(tests): don't auto-refresh while running unit tests

The test host is Stockbar.app itself, so its AppState used the real data
directory and kept refreshing (name sync, and soon price alerts).

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: NotificationService（系统通知）

**Files:**
- Create: `StockMonitor/Services/NotificationService.swift`
- Modify: `StockMonitor/StockMonitorApp.swift`（`applicationDidFinishLaunching`）
- Test: `StockMonitorTests/Services/NotificationServiceTests.swift`（新）

**Interfaces:**
- Consumes: `PriceAlertHit`（Task 1）；全局函数 `logToFile(_ message: String)`（`Utils/AppLogger.swift`）
- Produces:
  - `@MainActor protocol PriceAlertNotifier: AnyObject { func isAuthorized() async -> Bool; func notifyPriceReached(_ hit: PriceAlertHit) }`
  - `@MainActor final class NotificationService: NSObject, ObservableObject, PriceAlertNotifier`：`static let shared`、`@Published private(set) var status: UNAuthorizationStatus`、`func activate()`、`nonisolated static func isAllowed(_ status: UNAuthorizationStatus) -> Bool`、`func refreshStatus() async`、`func isAuthorized() async -> Bool`、`@discardableResult func requestAuthorizationIfNeeded() async -> Bool`、`func notifyPriceReached(_ hit: PriceAlertHit)`、`func sendTestNotification() async`、`func openSystemSettings()`

- [ ] **Step 1: 写失败的测试**

新建 `StockMonitorTests/Services/NotificationServiceTests.swift`：

```swift
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
```

- [ ] **Step 2: 运行，确认失败**

Run: 测试命令，`-only-testing:StockbarTests/NotificationServiceTests`
Expected: 编译失败，`error: cannot find 'NotificationService' in scope`，`** TEST FAILED **`

- [ ] **Step 3: 实现**

新建 `StockMonitor/Services/NotificationService.swift`：

```swift
import AppKit
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
```

`StockMonitor/StockMonitorApp.swift`，在 `applicationDidFinishLaunching` 里 `logToFile(…)` 那行之后加：

```swift
        NotificationService.shared.activate()
```

如果这一行报 `main actor-isolated … can not be referenced from a nonisolated context`，在 `class AppDelegate` 前加 `@MainActor`（它的方法都是主线程回调）。

- [ ] **Step 4: 运行，确认通过**

Run: 测试命令，**不带** `-only-testing`（全部测试；顺带确认测试宿主启动时 `activate()` 不出问题）
Expected: 全部 `passed`，`** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add StockMonitor/Services/NotificationService.swift StockMonitor/StockMonitorApp.swift \
        StockMonitorTests/Services/NotificationServiceTests.swift
git commit -F - <<'EOF'
feat(price-alert): add NotificationService for macOS notifications

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: 刷新后的到价检查

**Files:**
- Create: `StockMonitor/State/AppState+PriceAlert.swift`
- Modify: `StockMonitor/State/AppState.swift`（加 `notifier` 属性；`refresh()` 调检查）
- Test: `StockMonitorTests/State/PriceAlertCheckTests.swift`（新）

**Interfaces:**
- Consumes: `PriceAlert`、`PriceAlertHit`（Task 1）；`Stock.alert`（Task 2）；测试时无自动刷新（Task 3）；`PriceAlertNotifier`、`NotificationService.shared`（Task 4）；现有 `nonisolated static func AppState.usMarketSession(at:) -> String?`
- Produces:
  - `var AppState.notifier: PriceAlertNotifier`
  - `nonisolated static func AppState.isAStockCallAuction(at now: Date) -> Bool`
  - `nonisolated static func AppState.alertPrice(for stock: Stock, quote: Quote, now: Date) -> (price: Double, sessionLabel: String?)?`
  - `func AppState.checkPriceAlerts(now: Date = Date()) async`

- [ ] **Step 1: 写失败的测试**

新建 `StockMonitorTests/State/PriceAlertCheckTests.swift`：

```swift
import XCTest
@testable import Stockbar

/// 记录发出的到价通知；authorized 控制"有没有通知权限"
@MainActor
private final class FakeNotifier: PriceAlertNotifier {
    var authorized = true
    private(set) var hits: [PriceAlertHit] = []
    func isAuthorized() async -> Bool { authorized }
    func notifyPriceReached(_ hit: PriceAlertHit) { hits.append(hit) }
}

@MainActor
final class PriceAlertCheckTests: XCTestCase {
    var sut: AppState!
    var tmpDir: URL!
    private var notifier: FakeNotifier!

    override func setUp() {
        super.setUp()
        // 隔离真实数据目录（同 AppStateTests）
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StockbarTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        AppState.appSupportDirOverride = tmpDir
        sut = AppState()
        sut.stocks = []
        sut.quotes = [:]
        notifier = FakeNotifier()
        sut.notifier = notifier
    }

    override func tearDown() {
        sut = nil
        notifier = nil
        AppState.appSupportDirOverride = nil
        if let d = tmpDir { try? FileManager.default.removeItem(at: d) }
        tmpDir = nil
        super.tearDown()
    }

    // MARK: - 辅助

    private func date(_ tz: String, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: tz)!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// 2026-10-29（周四）北京时间 10:00，A股盘中
    private var aStockOpen: Date { date("Asia/Shanghai", 2026, 10, 29, 10, 0) }

    private let fallTo9_5 = PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true)

    private func stock(_ id: String, _ market: Market, _ alert: PriceAlert?) -> Stock {
        Stock(id: id, name: "股票\(id)", market: market, costPrice: nil, holdingShares: nil, alert: alert)
    }

    private func quote(_ id: String, _ price: Double, ext: Double? = nil) -> Quote {
        Quote(code: id, price: price, change: 0, changePercent: 0, updateTime: "", extendedPrice: ext)
    }

    private func savedStocks() throws -> [Stock] {
        let data = try Data(contentsOf: tmpDir.appendingPathComponent("stocks.json"))
        return try JSONDecoder().decode([Stock].self, from: data)
    }

    // MARK: - 触发

    func test_reached_notifiesOnceAndTurnsOff() async {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(notifier.hits, [PriceAlertHit(stockId: "sh600000", stockName: "股票sh600000",
                                                     price: 9.4, targetPrice: 9.5,
                                                     direction: .fall, sessionLabel: nil)])
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, false)

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(notifier.hits.count, 1, "只通知一次")
    }

    func test_reached_savesTurnedOffAlertToDisk() async throws {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(try savedStocks().first?.alert?.isEnabled, false)
    }

    func test_notReached_staysOn() async {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.6)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, true)
    }

    func test_noPermission_doesNotFireAndStaysOn() async {
        notifier.authorized = false
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, true)
    }

    func test_disabledAlert_isIgnored() async {
        sut.stocks = [stock("sh600000", .aStock, PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: false))]
        sut.quotes = ["sh600000": quote("sh600000", 9.0)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
    }

    func test_missingQuote_isSkipped() async {
        sut.stocks = [stock("sh600000", .aStock, PriceAlert(targetPrice: 9.5, direction: nil, isEnabled: true))]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertNil(sut.stocks[0].alert?.direction)
    }

    func test_nilDirection_isSetFromFirstPriceAndSaved() async throws {
        sut.stocks = [stock("sh600000", .aStock, PriceAlert(targetPrice: 9.5, direction: nil, isEnabled: true))]
        sut.quotes = ["sh600000": quote("sh600000", 10)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(sut.stocks[0].alert?.direction, .fall)
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(try savedStocks().first?.alert?.direction, .fall)
    }

    func test_multipleStocksReached_eachNotified() async {
        sut.stocks = [
            stock("sh600000", .aStock, fallTo9_5),
            stock("hk00700", .hkStock, PriceAlert(targetPrice: 400, direction: .rise, isEnabled: true)),
        ]
        sut.quotes = ["sh600000": quote("sh600000", 9.4), "hk00700": quote("hk00700", 401)]

        await sut.checkPriceAlerts(now: aStockOpen)
        XCTAssertEqual(Set(notifier.hits.map(\.stockId)), ["sh600000", "hk00700"])
        XCTAssertEqual(sut.stocks.map { $0.alert?.isEnabled }, [false, false])
    }

    // MARK: - 美股用哪个价格

    func test_usRegularSession_usesRegularPrice() async {
        // 2026-10-29（周四）ET 10:00 盘中：时段价（盘前遗留）不参与
        sut.stocks = [stock("usr_aapl", .usStock, PriceAlert(targetPrice: 182, direction: .rise, isEnabled: true))]
        sut.quotes = ["usr_aapl": quote("usr_aapl", 181, ext: 183)]

        await sut.checkPriceAlerts(now: date("America/New_York", 2026, 10, 29, 10, 0))
        XCTAssertTrue(notifier.hits.isEmpty)
    }

    func test_usAfterHours_usesExtendedPriceWithLabel() async {
        // 2026-10-29（周四）ET 17:00 盘后
        sut.stocks = [stock("usr_aapl", .usStock, PriceAlert(targetPrice: 182, direction: .rise, isEnabled: true))]
        sut.quotes = ["usr_aapl": quote("usr_aapl", 181, ext: 182.3)]

        await sut.checkPriceAlerts(now: date("America/New_York", 2026, 10, 29, 17, 0))
        XCTAssertEqual(notifier.hits.first?.price, 182.3)
        XCTAssertEqual(notifier.hits.first?.sessionLabel, "盘后")
    }

    func test_alertPrice_usWeekend_usesExtendedPriceLabelledAfterHours() {
        // 2026-10-31（周六）休市：用周五盘后价，标「盘后」
        let p = AppState.alertPrice(for: stock("usr_aapl", .usStock, nil),
                                    quote: quote("usr_aapl", 181, ext: 182.3),
                                    now: date("America/New_York", 2026, 10, 31, 12, 0))
        XCTAssertEqual(p?.price, 182.3)
        XCTAssertEqual(p?.sessionLabel, "盘后")
    }

    func test_alertPrice_usWithoutExtendedPrice_usesRegularPrice() {
        let p = AppState.alertPrice(for: stock("usr_aapl", .usStock, nil),
                                    quote: quote("usr_aapl", 181),
                                    now: date("America/New_York", 2026, 10, 29, 17, 0))
        XCTAssertEqual(p?.price, 181)
        XCTAssertNil(p?.sessionLabel)
    }

    func test_alertPrice_nonPositivePrice_isNil() {
        XCTAssertNil(AppState.alertPrice(for: stock("hk00700", .hkStock, nil),
                                         quote: quote("hk00700", 0), now: aStockOpen))
    }

    // MARK: - A股集合竞价

    func test_isAStockCallAuction_boundaries() {
        XCTAssertFalse(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 14)))
        XCTAssertTrue(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 15)))
        XCTAssertTrue(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 24)))
        XCTAssertFalse(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 29, 9, 25)))
        // 周六没有竞价
        XCTAssertFalse(AppState.isAStockCallAuction(at: date("Asia/Shanghai", 2026, 10, 31, 9, 20)))
    }

    func test_aStockCallAuction_skipsThenFiresFrom0925() async {
        sut.stocks = [stock("sh600000", .aStock, fallTo9_5)]
        sut.quotes = ["sh600000": quote("sh600000", 9.4)]

        await sut.checkPriceAlerts(now: date("Asia/Shanghai", 2026, 10, 29, 9, 20))
        XCTAssertTrue(notifier.hits.isEmpty)
        XCTAssertEqual(sut.stocks[0].alert?.isEnabled, true)

        await sut.checkPriceAlerts(now: date("Asia/Shanghai", 2026, 10, 29, 9, 25))
        XCTAssertEqual(notifier.hits.count, 1)
    }

    func test_callAuction_onlyAppliesToAStock() async {
        sut.stocks = [stock("hk00700", .hkStock, PriceAlert(targetPrice: 400, direction: .rise, isEnabled: true))]
        sut.quotes = ["hk00700": quote("hk00700", 401)]

        await sut.checkPriceAlerts(now: date("Asia/Shanghai", 2026, 10, 29, 9, 20))
        XCTAssertEqual(notifier.hits.count, 1)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: 测试命令，`-only-testing:StockbarTests/PriceAlertCheckTests`
Expected: 编译失败，`error: value of type 'AppState' has no member 'notifier'`、`… has no member 'checkPriceAlerts'` 等，`** TEST FAILED **`

- [ ] **Step 3: 实现**

新建 `StockMonitor/State/AppState+PriceAlert.swift`：

```swift
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
```

`StockMonitor/State/AppState.swift`，在「实时状态」一节（`@Published var hasError …` 那行）之后加：

```swift

    // MARK: - 到价提醒

    /// 发到价通知的对象；测试里替换成假实现
    var notifier: PriceAlertNotifier = NotificationService.shared
```

`refresh()` 里，把

```swift
            lastUpdateTime = Date()
            syncStockNamesFromQuotes()
```

改为

```swift
            lastUpdateTime = Date()
            syncStockNamesFromQuotes()
            await checkPriceAlerts()
```

- [ ] **Step 4: 运行，确认通过**

Run: 测试命令，**不带** `-only-testing`（全部测试）
Expected: `PriceAlertCheckTests` 16 条全部 `passed`，其余测试照常通过，`** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add StockMonitor/State/AppState+PriceAlert.swift StockMonitor/State/AppState.swift \
        StockMonitorTests/State/PriceAlertCheckTests.swift
git commit -F - <<'EOF'
feat(price-alert): check alerts after each refresh and notify once

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: 编辑页：设置目标价与开关

**Files:**
- Modify: `StockMonitor/State/AppState+PriceAlert.swift`（加 `editedAlert`、`saveEdit`）
- Create: `StockMonitor/Views/PriceAlertViews.swift`（`PriceAlertEditor`）
- Modify: `StockMonitor/Views/SettingsView.swift`（编辑状态、铅笔按钮、`inlineEditView`）
- Test: `StockMonitorTests/State/AppStateEditTests.swift`（新）

**Interfaces:**
- Consumes: `PriceAlert.parseTarget` / `edited` / `summary`（Task 1）；`AppState.alertPrice(for:quote:now:)`（Task 5）；`NotificationService.shared.status` / `refreshStatus()` / `openSystemSettings()` / `requestAuthorizationIfNeeded()`（Task 4）
- Produces:
  - `func AppState.editedAlert(for stock: Stock, targetText: String, isEnabled: Bool, now: Date = Date()) -> PriceAlert?`
  - `@discardableResult func AppState.saveEdit(stockId: String, cost: Double?, shares: Double?, alertTargetText: String, alertEnabled: Bool, now: Date = Date()) -> PriceAlert?`
  - `struct PriceAlertEditor: View`，初始化 `PriceAlertEditor(stock: Stock, targetText: Binding<String>, isEnabled: Binding<Bool>)`

- [ ] **Step 1: 写失败的测试**

新建 `StockMonitorTests/State/AppStateEditTests.swift`：

```swift
import XCTest
@testable import Stockbar

/// 编辑页「保存」：成本 / 股数写观察仓或真实持仓，提醒始终写在股票本身
@MainActor
final class AppStateEditTests: XCTestCase {
    var sut: AppState!
    var tmpDir: URL!

    override func setUp() {
        super.setUp()
        // 隔离真实数据目录（同 AppStateTests）
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StockbarTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        AppState.appSupportDirOverride = tmpDir
        sut = AppState()
        sut.stocks = []
        sut.quotes = [:]
    }

    override func tearDown() {
        sut = nil
        AppState.appSupportDirOverride = nil
        if let d = tmpDir { try? FileManager.default.removeItem(at: d) }
        tmpDir = nil
        super.tearDown()
    }

    private func date(_ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 29   // 周四
        c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeStock(alert: PriceAlert? = nil) -> Stock {
        Stock(id: "sh600000", name: "浦发银行", market: .aStock, costPrice: nil, holdingShares: nil, alert: alert)
    }

    private func setPrice(_ p: Double) {
        sut.quotes = ["sh600000": Quote(code: "sh600000", price: p, change: 0, changePercent: 0, updateTime: "")]
    }

    func test_saveEdit_realHoldings_writesHoldingAndAlertTogether() {
        sut.stocks = [makeStock()]
        setPrice(10)

        let saved = sut.saveEdit(stockId: "sh600000", cost: 8.5, shares: 1000,
                                 alertTargetText: "9.5", alertEnabled: true, now: date(10, 0))

        XCTAssertEqual(saved, PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))
        XCTAssertEqual(sut.stocks[0].costPrice, 8.5)
        XCTAssertEqual(sut.stocks[0].holdingShares, 1000)
        XCTAssertEqual(sut.stocks[0].alert, saved)
    }

    func test_saveEdit_watchlist_holdingToWatchlist_alertStaysOnStock() {
        sut.stocks = [makeStock()]
        sut.watchlists = [Watchlist(id: "wl1", name: "观察仓")]
        sut.config.activeWatchlistId = "wl1"
        setPrice(10)

        sut.saveEdit(stockId: "sh600000", cost: 8.5, shares: 1000,
                     alertTargetText: "9.5", alertEnabled: true, now: date(10, 0))

        XCTAssertEqual(sut.watchlists[0].entries["sh600000"]?.costPrice, 8.5)
        XCTAssertNil(sut.stocks[0].costPrice, "观察仓模式不改真实持仓")
        XCTAssertEqual(sut.stocks[0].alert?.targetPrice, 9.5)
    }

    func test_saveEdit_invalidTarget_removesAlert() {
        sut.stocks = [makeStock(alert: PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))]

        let saved = sut.saveEdit(stockId: "sh600000", cost: nil, shares: nil,
                                 alertTargetText: "9.5.", alertEnabled: true, now: date(10, 0))
        XCTAssertNil(saved)
        XCTAssertNil(sut.stocks[0].alert)
    }

    func test_saveEdit_onlyHoldingChanged_keepsAlertDirection() {
        // 价格已越过目标价（9.4 < 9.5，还没触发），只改成本价，方向不能翻成"涨到"
        sut.stocks = [makeStock(alert: PriceAlert(targetPrice: 9.5, direction: .fall, isEnabled: true))]
        setPrice(9.4)

        sut.saveEdit(stockId: "sh600000", cost: 8, shares: 100,
                     alertTargetText: "9.5", alertEnabled: true, now: date(10, 0))
        XCTAssertEqual(sut.stocks[0].alert?.direction, .fall)
    }

    func test_saveEdit_duringCallAuction_leavesDirectionForLater() {
        sut.stocks = [makeStock()]
        setPrice(10)

        let saved = sut.saveEdit(stockId: "sh600000", cost: nil, shares: nil,
                                 alertTargetText: "9.5", alertEnabled: true, now: date(9, 20))
        XCTAssertNil(saved?.direction)
        XCTAssertEqual(saved?.isEnabled, true)
    }

    func test_saveEdit_unknownStock_changesNothing() {
        sut.stocks = [makeStock()]

        XCTAssertNil(sut.saveEdit(stockId: "sh999999", cost: 1, shares: 1,
                                  alertTargetText: "9.5", alertEnabled: true, now: date(10, 0)))
        XCTAssertEqual(sut.stocks, [makeStock()])
    }

    func test_editedAlert_noQuote_leavesDirectionNil() {
        let a = sut.editedAlert(for: makeStock(), targetText: "9.5", isEnabled: true, now: date(10, 0))
        XCTAssertEqual(a, PriceAlert(targetPrice: 9.5, direction: nil, isEnabled: true))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: 测试命令，`-only-testing:StockbarTests/AppStateEditTests`
Expected: 编译失败，`error: value of type 'AppState' has no member 'saveEdit'` / `'editedAlert'`，`** TEST FAILED **`

- [ ] **Step 3: 实现 AppState 部分**

在 `StockMonitor/State/AppState+PriceAlert.swift` 的扩展里（`checkPriceAlerts` 之后、扩展结尾 `}` 之前）加：

```swift

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
```

- [ ] **Step 4: 运行，确认通过**

Run: 测试命令，`-only-testing:StockbarTests/AppStateEditTests`
Expected: 7 条全部 `passed`，`** TEST SUCCEEDED **`

- [ ] **Step 5: 实现编辑页控件**

新建 `StockMonitor/Views/PriceAlertViews.swift`：

```swift
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
```

开关用系统默认样式，和设置页其它开关一致，macOS 上显示为勾选框。

- [ ] **Step 6: 接入 SettingsView**

`StockMonitor/Views/SettingsView.swift`：

1. 在 `@State private var editShares    = ""` 之后加：

```swift
    @State private var editTarget    = ""
    @State private var editAlertOn   = false
```

2. `stockRow` 里铅笔按钮的 action，把

```swift
                editShares   = appState.effectiveShares(for: stock).map { String(Int($0)) } ?? ""
            } label: { Image(systemName: "pencil").font(.system(size: 11)) }
```

改为

```swift
                editShares   = appState.effectiveShares(for: stock).map { String(Int($0)) } ?? ""
                editTarget   = stock.alert.map { String($0.targetPrice) } ?? ""
                editAlertOn  = stock.alert?.isEnabled ?? false
            } label: { Image(systemName: "pencil").font(.system(size: 11)) }
```

3. `inlineEditView` 里，在「持仓股数」那个 `HStack { … }` 之后、`HStack { Button("取消") …` 之前加：

```swift
            Divider()
            // 传当前最新的股票（提醒可能在编辑期间被触发关闭）
            PriceAlertEditor(stock: appState.stocks.first(where: { $0.id == stock.id }) ?? stock,
                             targetText: $editTarget, isEnabled: $editAlertOn)
```

4. 把「保存」按钮整段

```swift
                Button("保存") {
                    let cost   = Double(editCost)
                    let shares = Double(editShares)
                    if let wlId = appState.config.activeWatchlistId,
                       let wlIdx = appState.watchlists.firstIndex(where: { $0.id == wlId }) {
                        // 写入观察仓
                        if let c = cost, let s = shares {
                            appState.watchlists[wlIdx].entries[stock.id] = WatchlistEntry(costPrice: c, holdingShares: s)
                        } else {
                            appState.watchlists[wlIdx].entries.removeValue(forKey: stock.id)
                        }
                    } else {
                        // 写入真实持仓
                        if let idx = appState.stocks.firstIndex(where: { $0.id == stock.id }) {
                            var updated = appState.stocks
                            updated[idx].costPrice     = cost
                            updated[idx].holdingShares = shares
                            appState.stocks = updated
                        }
                    }
                    editingStock = nil
                }.buttonStyle(.borderedProminent)
```

替换为

```swift
                Button("保存") {
                    let saved = appState.saveEdit(stockId: stock.id,
                                                  cost: Double(editCost), shares: Double(editShares),
                                                  alertTargetText: editTarget, alertEnabled: editAlertOn)
                    // 开着提醒时，第一次在这里申请通知权限
                    if saved?.isEnabled == true {
                        Task { await NotificationService.shared.requestAuthorizationIfNeeded() }
                    }
                    editingStock = nil
                }.buttonStyle(.borderedProminent)
```

- [ ] **Step 7: 运行全部测试**

Run: 测试命令，**不带** `-only-testing`
Expected: 全部 `passed`，`** TEST SUCCEEDED **`（界面在 Task 9 真机上验证；**不要**现在启动编出来的 App）

- [ ] **Step 8: 提交**

```bash
git add StockMonitor/State/AppState+PriceAlert.swift StockMonitor/Views/PriceAlertViews.swift \
        StockMonitor/Views/SettingsView.swift StockMonitorTests/State/AppStateEditTests.swift
git commit -F - <<'EOF'
feat(price-alert): set target price and toggle on the stock edit page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: 列表铃铛角标与「到价提醒」设置分组

**Files:**
- Modify: `StockMonitor/Views/StockRowView.swift`
- Modify: `StockMonitor/Views/SettingsView.swift`（`stockRow` 说明行；新分组）
- Modify: `StockMonitor/Views/PriceAlertViews.swift`（加 `PriceAlertPermissionRow`）
- Test: 纯界面，无新单测；`summary` / `badge` 已在 Task 1 覆盖

**Interfaces:**
- Consumes: `PriceAlert.summary` / `badge`（Task 1）；`NotificationService.shared` 的 `status` / `refreshStatus()` / `sendTestNotification()` / `openSystemSettings()` / `isAllowed(_:)`（Task 4）
- Produces: `struct PriceAlertPermissionRow: View`（无参数初始化）

- [ ] **Step 1: 主列表角标**

`StockMonitor/Views/StockRowView.swift`，把

```swift
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
```

替换为

```swift
                HStack(spacing: 3) {
                    Text(stock.id)
                    // 开启了到价提醒：小铃铛 + 方向 + 目标价
                    if let alert = stock.alert, alert.isEnabled {
                        Image(systemName: "bell.fill")
                        Text(alert.badge)
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
```

- [ ] **Step 2: 「我的股票」说明行**

`StockMonitor/Views/SettingsView.swift` 的 `stockRow`，把

```swift
                } else {
                    Text("未设置持仓").font(.caption).foregroundColor(.secondary)
                }
```

替换为

```swift
                } else {
                    Text("未设置持仓").font(.caption).foregroundColor(.secondary)
                }
                if let alert = stock.alert, alert.isEnabled {
                    Label(alert.summary, systemImage: "bell.fill")
                        .font(.caption).foregroundColor(.accentColor)
                }
```

- [ ] **Step 3: 权限行视图**

在 `StockMonitor/Views/PriceAlertViews.swift` 末尾加：

```swift

/// 设置页「到价提醒」分组：通知权限状态 + 测试 / 授权 / 打开系统设置
@MainActor
struct PriceAlertPermissionRow: View {
    @ObservedObject private var notifications = NotificationService.shared

    var body: some View {
        HStack {
            Text("通知权限：\(statusText)").font(.system(size: 12))
            Spacer()
            actionButton
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .task { await notifications.refreshStatus() }
    }

    private var statusText: String {
        if NotificationService.isAllowed(notifications.status) { return "已开启" }
        return notifications.status == .denied ? "已关闭" : "未授权"
    }

    @ViewBuilder
    private var actionButton: some View {
        if notifications.status == .denied {
            Button("打开系统设置") { notifications.openSystemSettings() }
        } else if NotificationService.isAllowed(notifications.status) {
            Button("发送测试通知") { Task { await notifications.sendTestNotification() } }
        } else {
            Button("授权并测试") { Task { await notifications.sendTestNotification() } }
        }
    }
}
```

- [ ] **Step 4: 加设置分组**

`StockMonitor/Views/SettingsView.swift`，在

```swift
                // 开机启动
                section("开机启动") {
```

之前加：

```swift
                // 到价提醒：通知权限 + 测试
                section("到价提醒") {
                    PriceAlertPermissionRow()
                }

```

- [ ] **Step 5: 运行全部测试**

Run: 测试命令，**不带** `-only-testing`
Expected: 全部 `passed`，`** TEST SUCCEEDED **`

- [ ] **Step 6: 提交**

```bash
git add StockMonitor/Views/StockRowView.swift StockMonitor/Views/SettingsView.swift \
        StockMonitor/Views/PriceAlertViews.swift
git commit -F - <<'EOF'
feat(price-alert): show alert badges and a notification permission row

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 8: 发布签名与文档

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `README.md`、`README_CN.md`
- Modify（本地，不提交）：`CLAUDE.md`；`/Users/vgearen/.claude/projects/-Users-vgearen-workspace-AiProjects-stock-monitor/memory/reference_build_dmg.md`

**Interfaces:**
- Consumes: 前面所有任务（完整功能）
- Produces: 签名校验通过的 Release 包 `/tmp/stockbar_build/…/Stockbar.app`（Task 9 用）

- [ ] **Step 1: CI 加签名步骤**

`.github/workflows/release.yml`，在 `- name: Locate .app` 这一步（到 `echo "app_path=$APP_PATH" >> "$GITHUB_OUTPUT"` 为止）之后、`- name: Create DMG` 之前插入：

```yaml
      - name: Ad-hoc sign (required for notifications)
        run: |
          # 未签名的包申请不到系统通知权限（UNErrorDomain Code=1），必须补完整 ad-hoc 签名
          APP_PATH="${{ steps.locate.outputs.app_path }}"
          codesign --force --deep --sign - "$APP_PATH"
          codesign --verify --deep --strict --verbose=2 "$APP_PATH"
          codesign -dv "$APP_PATH" 2>&1 | grep -q "^Identifier=com.vgearen.Stockbar$"

```

- [ ] **Step 2: 本地按同样步骤编 Release 并签名**

```bash
xcodebuild -project StockMonitor.xcodeproj -scheme Stockbar -configuration Release \
  -derivedDataPath /tmp/stockbar_build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "\.swift:[0-9]+:[0-9]+: error:|BUILD (SUCCEEDED|FAILED)"
APP_PATH=$(find /tmp/stockbar_build -name "Stockbar.app" -maxdepth 6 | head -1)
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv "$APP_PATH" 2>&1 | grep -q "^Identifier=com.vgearen.Stockbar$" && echo "identifier OK"
for a in arm64 x86_64; do echo "== $a"; codesign -dv --arch $a "$APP_PATH" 2>&1 | grep -E "^Identifier|^Signature|flags="; done
```

Expected：`** BUILD SUCCEEDED **`；`valid on disk` 和 `satisfies its Designated Requirement`；`identifier OK`；两个切片都是 `Identifier=com.vgearen.Stockbar`、`Signature=adhoc`，flags 里不再有 `linker-signed`。

- [ ] **Step 3: README_CN.md**

「功能特性」里，在 `- **持仓盈亏跟踪** — …` 那行之后加：

```markdown
- **到价提醒** — 给股票设一个目标价，涨到或跌到时弹出 macOS 系统通知；每只股票单独开关，提醒一次后自动关闭
```

「使用说明」里，在 `### 分时走势图` 之前加：

```markdown
### 到价提醒

1. 在 **设置 → 我的股票** 中点击铅笔图标
2. 填写 **目标价**，勾选 **到价提醒** 后保存：目标价高于现价时等它涨到，低于现价时等它跌到
3. 到价后弹出系统通知，这只股票的提醒随即自动关闭（只提醒一次）；开启中的提醒在列表里显示 🔔

> 第一次开启时 macOS 会询问是否允许 Stockbar 发送通知，请点 **允许**；也可以在 **设置 → 到价提醒** 发送测试通知确认。Stockbar 需要放在 **应用程序** 文件夹里才能收到通知。

```

- [ ] **Step 4: README.md**

「Features」里，在 `- **Portfolio P&L** — …` 那行之后加：

```markdown
- **Price alerts** — Set a target price per stock and get a macOS notification when it rises or falls to it; each stock has its own toggle, and an alert switches itself off after firing once
```

「Usage」里，在 `### Intraday chart` 之前加：

```markdown
### Price alerts

1. In **Settings → My Stocks**, click the pencil icon next to a stock
2. Enter a **target price**, check **到价提醒** (price alert) and save — if the target is above the current price Stockbar waits for the price to rise to it, otherwise to fall to it
3. When the price gets there you get a system notification and the alert switches off (it fires only once); stocks with an active alert show 🔔 in the list

> The first time you turn on an alert, macOS asks whether Stockbar may send notifications — click **Allow**. You can send a test notification from **Settings → 到价提醒**. Stockbar must be in the **Applications** folder to receive notifications.

```

- [ ] **Step 5: CLAUDE.md（本地，不提交）**

1. 「项目结构」：`Models/` 下加 `│   ├── PriceAlert.swift   # 到价提醒（目标价/方向/开关、判断规则、通知文案）`；`State/` 改为 `│   ├── AppState.swift` + `│   └── AppState+PriceAlert.swift  # 到价检查、编辑页保存`；`Services/` 下加 `│   ├── NotificationService.swift # 系统通知（UNUserNotificationCenter）`；`Views/` 下加 `│   ├── PriceAlertViews.swift  # 编辑页提醒控件、设置页通知权限行`
2. 「数据持久化」：加一行 `- stocks.json 每只股票可带 alert 字段（到价提醒），解码容错，旧文件兼容`
3. 「本地打 DMG」代码块：在 `APP_PATH=…` 那行之后加

```bash
# 补完整 ad-hoc 签名（系统通知必需，见踩坑 15）
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

4. 「历史重要决策与踩坑记录」末尾加：

```markdown
### 15. 到价提醒：系统通知与签名
- 只有链接器签名（`CODE_SIGNING_ALLOWED=NO` 编出来的默认状态）的包，`requestAuthorization` 直接返回 `UNErrorDomain Code=1`，连授权弹窗都不会出现
- 必须 `codesign --force --deep --sign -` 补完整 ad-hoc 签名（CI 已在打 DMG 前做并校验）
- App 还必须在「应用程序」目录：放在 /tmp 时 usernoted 报 `Failed to find or validate client`
- 同一 Bundle ID 登记了多份（如测试宿主 `/tmp/stockbar_test_dd/…/Stockbar.app`）时，用 `lsregister -u <路径>` 清掉多余的
- 测试宿主就是 Stockbar.app，`AppState.isRunningUnitTests` 为 true 时不启动自动刷新，避免测试用真实数据跑到价检查
- A股 9:15–9:25 集合竞价价格不参与到价判断和定方向；美股盘外时段用时段价
```

5. 「已知问题与注意事项」第 2 条改为：`2. **未公证（ad-hoc 签名）**：首次启动需在「系统设置 → 隐私与安全性」手动允许。`

- [ ] **Step 6: 打包备忘（本地，不提交）**

`/Users/vgearen/.claude/projects/-Users-vgearen-workspace-AiProjects-stock-monitor/memory/reference_build_dmg.md`，在 `APP_PATH=$(find …)` 那行之后加：

```bash
# 补完整 ad-hoc 签名（系统通知必需；未签名的包申请不到通知权限）
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

- [ ] **Step 7: 确认 CLAUDE.md 没被暂存，然后提交**

```bash
git status --short   # 应只有 release.yml、README.md、README_CN.md；CLAUDE.md 被忽略不出现
git add .github/workflows/release.yml README.md README_CN.md
git commit -F - <<'EOF'
build(release): ad-hoc sign the app so it can request notifications

Also document price alerts in both READMEs.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 9: 真机验证（需要用户配合）

**会动到用户的 /Applications/Stockbar.app，开始前必须先问用户并得到同意。** 告诉用户：会退出正在运行的旧版 Stockbar，把旧版打包备份，换成新版启动；之后要他们点一次通知授权的「允许」，并在设置里操作几步。

**Files:** 无代码改动

- [ ] **Step 1: 征得用户同意**（不同意就停在这里，汇报 Task 1–8 的结果）

- [ ] **Step 2: 清理多余的 LaunchServices 登记**

```bash
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSREG -dump | grep -iE "^path:.*stockbar\.app" | sort -u
# 对列出的每个不在 /Applications 下的路径（如 /private/tmp/stockbar_test_dd/Build/Products/Debug/Stockbar.app）执行：
$LSREG -u "/private/tmp/stockbar_test_dd/Build/Products/Debug/Stockbar.app"
```

Expected：再执行一次 `-dump | grep`，只剩 `/Applications/Stockbar.app`。

- [ ] **Step 3: 退出旧版并备份**

```bash
# 不用 osascript quit：那会触发系统「自动化」权限弹窗。App 每次改动都原子写盘，直接结束进程是安全的
pkill -x Stockbar; sleep 2
pgrep -x Stockbar && echo "STILL RUNNING" || echo "quit OK"
BK="$HOME/Library/Application Support/Stockbar/manual-backups"
OLD_VER=$(defaults read /Applications/Stockbar.app/Contents/Info.plist CFBundleShortVersionString)
ditto -c -k --keepParent /Applications/Stockbar.app "$BK/Stockbar-$OLD_VER.app.zip" && ls -la "$BK"
```

Expected：`quit OK`；`manual-backups/` 下出现 `Stockbar-1.3.8.app.zip`。备份用 zip，不留第二个 .app，免得系统又多登记一份。

- [ ] **Step 4: 安装新版并启动**

```bash
APP_PATH=$(find /tmp/stockbar_build -name "Stockbar.app" -maxdepth 6 | head -1)
rm -rf /Applications/Stockbar.app && ditto "$APP_PATH" /Applications/Stockbar.app
codesign --verify --deep --strict /Applications/Stockbar.app && echo "installed signature OK"
$LSREG -u "$APP_PATH"; $LSREG -f /Applications/Stockbar.app
open /Applications/Stockbar.app
```

Expected：`installed signature OK`；菜单栏出现奶牛图标，列表和以前一样（38 只股票都在）。

- [ ] **Step 5: 授权与测试通知（用户操作）**

请用户：菜单栏图标 → ⚙ 设置 → 「到价提醒」→ 点「授权并测试」→ 右上角弹授权请求时点「允许」。
Expected：看到「Stockbar 测试通知」横幅；设置页显示「通知权限：已开启」。
没出现时查日志：`tail -20 ~/Library/Logs/Stockbar/app.log`（找 `NotificationService:`），以及：

```bash
/usr/bin/log show --last 5m --style compact --predicate 'process == "usernoted" AND eventMessage CONTAINS[c] "com.vgearen.Stockbar"' | tail -20
```

- [ ] **Step 6: 到价通知（用户操作）**

请用户：设置 → 我的股票 → 任选一只股票点 ✏️ → 目标价填它**当前的价格** → 勾选「到价提醒」→ 保存，**面板不要关**。
Expected：几秒内（下一次刷新）收到「<股票名> 到价提醒」横幅（面板开着也弹出，验证 `willPresent`）；这只股票的 🔔 从「我的股票」和主列表消失；再打开编辑页，「到价提醒」为未勾选，目标价还在。

- [ ] **Step 7: 重启不重复**

```bash
pkill -x Stockbar; sleep 2; open /Applications/Stockbar.app; sleep 15
```

Expected：没有新的到价通知。

- [ ] **Step 8: 汇报**

向用户汇报每一步的实际结果（包括失败），并告知：
- 回滚方法：退出 Stockbar → `rm -rf /Applications/Stockbar.app` → 解压 `manual-backups/Stockbar-1.3.8.app.zip` 到 /Applications
- 测试用的那只股票还留着目标价（提醒已关），不需要的话在编辑页清空目标价保存即可
- 分支 `feat/price-alert` 只在本地；是否合并到 main、是否改版本号（建议 1.4.0）和发版由用户决定
