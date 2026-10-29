# 到价提醒设计稿

- **日期**：2026-10-29
- **范围**：每只股票可设一个目标价，价格涨到 / 跌到目标价时发 macOS 系统通知；只通知一次，通知后该股票的提醒开关自动关闭
- **方案**：提醒数据挂在 `Stock` 上（随 stocks.json 持久化），`AppState.refresh()` 后检查；`UNUserNotificationCenter` 发通知；发布包补 ad-hoc 签名

---

## 1. 背景

用户希望给股票设目标价，到价时收到 Mac 的系统通知弹窗。

**前期验证**（2026-10-29，macOS 27.0.1，Apple Silicon）：

当前发布包没有有效签名：`codesign --verify` 报 `code object is not signed at all`。arm64 切片只有链接器自动加的 ad-hoc 签名（`linker-signed`、`Identifier=Stockbar`、`Info.plist=not bound`），x86_64 切片完全未签名。

用一次性测试 App 调 `UNUserNotificationCenter.requestAuthorization` 的结果：

| 签名 | 位置 | 结果 |
|------|------|------|
| 仅链接器签名（同当前发布包） | /tmp、~/Applications | ❌ 立即返回 `UNErrorDomain Code=1`，请求没有到达 usernoted |
| 完整 ad-hoc（`codesign --force --deep --sign -`） | /tmp | ❌ usernoted：`Failed to find or validate client` |
| 完整 ad-hoc | ~/Applications | ✅ usernoted 发出授权请求（`Sending request for permission … with path …`），系统弹出授权横幅 |

结论：系统通知需要 **完整 ad-hoc 签名 + App 位于「应用程序」目录**。正常安装（拖进 /Applications）满足位置要求；发布流程需要补签名步骤。

---

## 2. 设计目标

1. 每只股票可设一个目标价，方向（涨到 / 跌到）自动判断
2. 到价发 macOS 系统通知（横幅 + 提示音，进通知中心）
3. 每只股票一个提醒开关；通知只发一次，发完自动关闭开关
4. 不影响现有行情刷新、持仓、观察仓逻辑；旧 stocks.json 无缝兼容
5. 发布包能正常申请通知权限

**非目标**：

- 同时设上限 + 下限两个价
- 强制通知样式为「提醒」（Info.plist `NSUserNotificationAlertStyle`）
- 点击通知打开下拉面板
- 提醒历史记录
- A股收盘集合竞价（14:57–15:00）、港股开市前竞价的特殊处理

---

## 3. 数据模型

### 3.1 PriceAlert（新文件 `Models/PriceAlert.swift`）

```swift
/// 到价提醒：目标价 + 自动判断的方向 + 开关
struct PriceAlert: Codable, Equatable {
    enum Direction: String, Codable { case rise, fall }   // 涨到 / 跌到

    var targetPrice: Double
    var direction: Direction?   // nil = 布防时还没有可用价格，首次拿到价格时再定
    var isEnabled: Bool         // 这只股票的提醒开关
}
```

`Stock` 新增 `var alert: PriceAlert? = nil`。有默认值，现有 `Stock(id:name:market:costPrice:holdingShares:)` 调用不用改。

同一文件里还放：方向判断、到价判断、编辑生成规则（4.2、4.3 的纯函数）和 `PriceAlertHit`（5.1）。

### 3.2 持久化兼容

- `Stock.CodingKeys` 加 `alert`；`init(from:)` 用 `try? c.decodeIfPresent(PriceAlert.self, forKey: .alert)`：
  - 旧 stocks.json 没有这个字段 → `nil`
  - 字段损坏 → 只丢这只股票的提醒。`loadStocks()` 只要有一条 `Stock` 解码失败就整体返回 `[]`，所以这里必须容错
- 编码沿用合成的 `encode(to:)`，`nil` 时不写字段
- 提醒属于股票本身，不进观察仓（`Watchlist.entries` 不变）；删除股票时提醒一起删除

---

## 4. 触发规则

### 4.1 判断用的价格

`AppState.alertPrice(for:quote:now:) -> (price: Double, sessionLabel: String?)?`，返回 `nil` 表示这一次不判断：

| 市场 | 价格 | sessionLabel |
|------|------|------|
| A股 / 港股 / 韩股 | `quote.price` | nil |
| 美股 盘中 | `quote.price`（正盘价） | nil |
| 美股 盘前 / 盘后 | 有 `quote.extendedPrice` 用时段价，否则 `quote.price` | 用时段价时为 "盘前" / "盘后" |
| 美股 夜盘 | 有夜盘价用夜盘价；拿不到夜盘价时返回 nil（这次不判断），因为此时 `quote.price` 是过时的正盘收盘价 | "夜盘" |
| 美股 休市（周末等，`usMarketSession` 为 nil） | 同上 | 用时段价时为 "盘后" |

返回 `nil` 的情况：

- 价格 ≤ 0
- **A股集合竞价**：北京时间周一至周五 09:15 ≤ t < 09:25。这段时间是虚拟撮合价，会随撤单跳动；既不用来判断到价，也不用来定方向
- **美股夜盘拿不到夜盘价**（请求失败 / 还没成交 / 不支持夜盘）

### 4.2 方向

- `PriceAlert.direction(target:currentPrice:)`：目标价 ≥ 现价 → `.rise`，否则 → `.fall`
- 编辑页保存时由 `PriceAlert.edited(previous:targetPrice:isEnabled:currentPrice:)` 生成新提醒：
  - **重新布防**（新建并开启 / 开关从关到开 / 开启状态下改了目标价）→ 用 4.1 的价格定方向；拿不到价格 → `nil`
  - 其它情况（开关一直开着、目标价没变，比如只改了成本价）→ 保持原方向。否则价格已经越过目标价时重新判断，会把方向弄反
- 检查时（不需要通知权限）如果 `direction == nil` 且拿到了有效价格 → 用这个价格定方向并保存

### 4.3 到价

`PriceAlert.isReached(by:)`：开关开启、方向已定、价格 > 0 时，`.rise` 为 价格 ≥ 目标价，`.fall` 为 价格 ≤ 目标价。正好等于目标价算到价。

### 4.4 检查流程

`AppState.checkPriceAlerts(now: Date = Date()) async`，在 `refresh()` 合并完行情、同步完名称后调用：

1. 没有任何开启的提醒 → 直接返回（不做权限查询）
2. 给方向为 `nil`、已有可用价格的开启中提醒定方向，有变化就保存（不需要通知权限）
3. `await notifier.isAuthorized()` 为 false → 返回，**开关保持开启**，授权后再触发
4. 遍历开启提醒的股票：取 4.1 的价格（`nil` 跳过）→ `isReached` 则 `isEnabled = false`，记入待通知列表
5. 有变化时一次性 `stocks = updated`（触发 didSet 保存）
6. 保存之后再逐条 `notifier.notifyPriceReached(hit)`

先存后发：就算发通知时 App 退出，重启后也不会重复通知。第 4–6 步在 MainActor 上同步执行，两次 refresh 重叠时也不会重复触发。

App 没运行期间价格已经到了：下次启动第一次刷新就会触发。

---

## 5. 通知

### 5.1 接口

```swift
@MainActor
protocol PriceAlertNotifier: AnyObject {
    func isAuthorized() async -> Bool
    func notifyPriceReached(_ hit: PriceAlertHit)
}

/// 一次到价，包含拼通知文案需要的全部信息
struct PriceAlertHit: Equatable {
    let stockId: String
    let stockName: String
    let price: Double
    let targetPrice: Double
    let direction: PriceAlert.Direction
    let sessionLabel: String?   // 美股用时段价时为 "盘前"/"盘后"/"夜盘"

    var title: String   // "浦发银行 到价提醒"
    var body: String    // "现价 9.480，已跌到目标价 9.500" / "盘后 182.30，已涨到目标价 182.00"
}
```

`AppState` 持有 `var notifier: PriceAlertNotifier = NotificationService.shared`，测试时注入假实现。

价格格式沿用 `Quote.formattedPrice` 的规则（≥ 10 保留两位小数，否则三位），抽成 `Quote.format(_:)` 复用。

### 5.2 NotificationService（新文件 `Services/NotificationService.swift`）

- `ObservableObject` 单例（写法同 `UpdateChecker.shared`），`@Published status: UNAuthorizationStatus` 供界面显示
- `activate()`：在 `AppDelegate.applicationDidFinishLaunching` 里设置 `UNUserNotificationCenter.current().delegate`
- `willPresent` 返回 `[.banner, .sound, .list]`：下拉面板打开（App 在前台）时也照常弹横幅
- `refreshStatus()` / `isAuthorized()`：读 `getNotificationSettings`，`.authorized` / `.provisional` 视为有权限
- `requestAuthorizationIfNeeded()`：只在 `.notDetermined` 时调 `requestAuthorization([.alert, .sound])`；失败写日志
- `notifyPriceReached(_:)`：`UNMutableNotificationContent`（标题、正文、`.default` 提示音、threadIdentifier `price-alert`），立即投递；`add` 失败写日志
- `sendTestNotification()`：未授权时先申请，再发一条「Stockbar 测试通知」
- `openSystemSettings()`：打开 `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=<bundleId>`

### 5.3 权限申请时机

- 启动时不申请
- 编辑页保存时，提醒为开启且状态为 `.notDetermined` → 申请
- 设置页「授权并测试」→ 申请并发测试通知
- 被拒绝（`.denied`）：编辑页和设置页显示「通知未开启」+「打开系统设置」；提醒保持开启

---

## 6. UI

### 6.1 编辑页（设置 → 我的股票 → ✏️）

在「持仓股数」下面加分隔线和：

```
☑ 到价提醒
目标价      [ 9.5         ]
现价 10.02，跌到 9.500 时提醒
⚠️ 通知未开启 [打开系统设置]    ← 仅 .denied 时显示
```

- 开关用系统默认样式（macOS 上是勾选框），和设置页其它开关一致
- 目标价为空或不是正数时，开关显示为关闭并禁用（不改动勾选状态，输入途中短暂无效不会丢掉勾选）；清空目标价并保存 = 删除提醒（`alert = nil`）
- 编辑页开着时提醒被触发（自动关闭），勾选框随之取消，避免点保存时反向重新布防
- 成本价、股数不是有限数（如 `inf`、`nan`）时视为未填，避免编码失败导致之后的保存全部丢失
- 目标价非空但格式不对（如 `9.5.`、`abc`）：提示文字显示红色「请输入有效的目标价」；仍然保存的话视同清空（和现有成本价输入框的处理一致）
- 提示文字用 `PriceAlert.edited(…)` 实时算出保存后的方向：`涨到 X 时提醒` / `跌到 X 时提醒`；有价格时前面加 `现价 Y，`（美股时段价为 `盘后 Y，` 等）；方向未定时显示「暂无可用价格，拿到价格后自动判断涨到还是跌到」
- 保存：成本价、股数沿用现有逻辑；提醒**始终写入 `appState.stocks` 中这只股票的 `alert`**
  - 真实持仓：成本、股数和提醒合并成一次 `stocks` 赋值，只保存、备份一次
  - 观察仓：成本、股数写 `watchlists`，提醒写 `stocks`，各保存一次
- 提醒相关控件抽成独立视图（新文件 `Views/PriceAlertViews.swift`），避免已有 565 行的 `SettingsView` 继续变大

### 6.2 主列表（StockRowView）

开启提醒时，代码那一行后面加 `bell.fill` 图标 + 方向箭头 + 目标价（9pt，次要颜色），如 `sh600000 🔔↓9.500`；方向未定时不显示箭头。

### 6.3 设置页「我的股票」

开启提醒的股票，在「成本 …」下面多一行 `🔔 跌到 9.500`（方向未定时为 `🔔 目标 9.500`）。

### 6.4 设置页「到价提醒」分组（放在「开机启动」上面）

| 权限状态 | 文案 | 按钮 |
|------|------|------|
| `.authorized` / `.provisional` | 通知权限：已开启 | 发送测试通知 |
| `.notDetermined` | 通知权限：未授权 | 授权并测试 |
| `.denied` | 通知权限：已关闭 | 打开系统设置 |

每次进入设置页刷新一次权限状态。

---

## 7. 打包签名

### 7.1 CI（`.github/workflows/release.yml`）

在「Locate .app」之后、「Create DMG」之前新增一步：

```yaml
      - name: Ad-hoc sign (required for notifications)
        run: |
          APP_PATH="${{ steps.locate.outputs.app_path }}"
          codesign --force --deep --sign - "$APP_PATH"
          codesign --verify --deep --strict --verbose=2 "$APP_PATH"
          codesign -dv "$APP_PATH" 2>&1 | grep -q "^Identifier=com.vgearen.Stockbar$"
```

任一命令失败，CI 就失败，不会发出收不到通知的包。

### 7.2 本地

CLAUDE.md 的「本地构建 / 本地打 DMG」和打包备忘，在 xcodebuild 和 hdiutil 之间加上同样的签名、校验命令。

### 7.3 影响

- 自动更新：`copyItem` + `cp -R` 复制整个 .app，签名随之保留
- Gatekeeper：仍未公证，首次打开仍需在「隐私与安全性」里允许，和现在一样
- 签名标识从 `Stockbar` 变为 `com.vgearen.Stockbar`，两个切片都有签名
- `xcodebuild test` 命令不变（测试不依赖通知权限）

---

## 8. 测试

### 8.1 测试隔离

单元测试的宿主是 Stockbar.app 本身（`TEST_HOST`）。宿主里的 `AppState` 用的是**真实数据目录**并会定时刷新。加入到价检查后，如果宿主进程拿到了通知权限，可能触发并关掉用户真实的提醒；现有的 `syncStockNamesFromQuotes` 也可能在测试期间写真实的 stocks.json。

处理：`AppState.init` 检测到运行在 XCTest 中时不启动定时刷新。测试里自建的 `AppState` 同样不刷新，测试更确定；`RefreshSchedulerTests` 直接测调度器，不受影响。

检测方式（2026-10-29 用临时探针测试实测，Xcode 27.1）：宿主进程里 `XCTestConfigurationFilePath` 存在但值为空字符串，`XCTestSessionIdentifier` 有值（UUID）。两者任一存在即视为在跑测试。环境变量在进程启动时就已设好，不受 `AppState` 初始化时机影响。

### 8.2 单元测试

| Suite | 范围 |
|------|------|
| `PriceAlertTests`（新） | `direction`：目标价高于 / 低于 / 等于现价；`isReached`：涨到、跌到边界（等于目标价算到价）、开关关闭、方向未定、价格 ≤ 0；`edited`：新建、关→开、改目标价重新判断、只改其它时保持方向、无价格时为 nil；`PriceAlertHit` 标题和正文 |
| `StockTests`（扩展） | 旧 JSON 没有 alert 字段；alert 往返编解码；alert 字段损坏时其它字段照常读出 |
| `PriceAlertCheckTests`（新） | 假 notifier + 临时目录：到价发一次并关闭、写回 stocks.json，再检查不重复发；未到价不发；无权限不发且保持开启；方向为 nil 时补齐并保存；美股盘中用正盘价、盘后用时段价并带 sessionLabel；A股 09:15–09:25 不判断、09:25 起判断；多只同时到价各发一条 |

命令同 CI：

```bash
xcodebuild test -project StockMonitor.xcodeproj -scheme Stockbar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### 8.3 打包验证

Release 通用二进制 + ad-hoc 签名：`codesign --verify --deep --strict` 通过，`Identifier=com.vgearen.Stockbar`，arm64 和 x86_64 切片都已签名。

### 8.4 真机验证（需要用户配合，执行前先确认）

1. 退出运行中的旧版，**先备份 /Applications/Stockbar.app**，再装入新版并启动
2. 设置 → 到价提醒 → 授权并测试 → 点「允许」→ 看到测试横幅
3. 任选一只股票，目标价设为现价并开启 → 下一次刷新收到到价通知 → 开关自动关闭，主列表铃铛消失
4. 下拉面板开着时触发，横幅照常弹出
5. 重启 App，已触发的提醒不再通知
6. 出问题时用备份的旧版恢复

---

## 9. 文档

- README（中 / 英）：「功能特性」加一条到价提醒；「使用说明」加「到价提醒」小节，写明首次需要授权、App 需放在「应用程序」文件夹里
- CLAUDE.md（本地，不提交）：项目结构、数据持久化、构建打包命令、踩坑记录（签名与通知）

---

## 10. 已知风险

| 风险 | 缓解 |
|------|------|
| 未公证的 ad-hoc 签名在以后的 macOS 上被进一步限制 | CI 签名后校验；设置页「发送测试通知」随时自查 |
| App 不在「应用程序」目录时收不到通知 | 正常安装满足；README 写明 |
| 横幅几秒后收起，可能错过 | 留在通知中心；可在系统设置里改成「提醒」样式 |
| 美股盘前 / 盘后 / 夜盘流动性差，时段价可能短暂冲到目标价 | 用户已确认接受；通知里标注时段 |
| A股收盘集合竞价、港股开市前竞价未特殊处理 | 非目标；有需要再加 |
| 勿扰 / 专注模式下通知被系统静默 | 系统行为；仍会进通知中心 |
| 时段切换后（ET 16:00 / 04:00 刚过）新浪 field[21] 在第一笔成交前可能仍是上一时段的价格 | 已知风险；后续可用 field[24] 时间戳与时段开始时间比对 |

---

## 11. 版本号

预计 `v1.4.0`（新功能）。是否发版、何时打 tag 由用户决定。
