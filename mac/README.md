# 下班倒计时 — 源码说明

一个 macOS 原生菜单栏 + 悬浮窗小应用，Swift 5 / SwiftUI + AppKit，最低 macOS 13。

> 整体架构（模块分层、数据流、生命周期、设计决策、技术债）见 [ARCHITECTURE.md](ARCHITECTURE.md)；本文偏构建与逐模块实现细节。
> 模块文档见 [docs/](docs/)，版本时间线见 [CHANGELOG.md](CHANGELOG.md)，许可见 [LICENSE](LICENSE)。

## 构建

```bash
cd 其他/OffWorkCountdown
./build.sh
```

产物：`其他/下班倒计时.app`（已 ad-hoc 签名，可直接双击）。
需要 Xcode 或 Command Line Tools（用到 `swiftc`、`iconutil`、`sips`、`codesign`、`plutil`）。

## 目录

| 文件 / 目录 | 作用 |
| --- | --- |
| `Sources/main.swift` | **只放顶层代码**：启动入口 + `--version-check` / `--hotkey-check` / `--selftest` 三个分支（Swift 规定顶层可执行语句只能出现在 `main.swift`） |
| `Sources/App/` | `HotKey.swift`（Carbon 全局热键）、`Store.swift`（数据仓库 / 登录自启同步）、`FloatingPanel.swift`、`AppDelegate.swift`（生命周期 / 菜单栏 / Popover） |
| `Sources/Model/` | `Prefs.swift`（偏好模型与向后兼容解码）、`Time.swift`（时间工具、状态模型、语录池、班次与进度纯计算） |
| `Sources/MenuBar/` | `Ring.swift`（`RingStatusView` 自绘进度环、色点与百分比绘制参数） |
| `Sources/UI/` | `Theme.swift`（语义色）、`Components.swift`、`PanelRoot.swift`、`SettingsComponents.swift`、`MenuView.swift` |
| `Sources/Tests/` | `SelfTest.swift`（58 项纯函数回归自测） |
| `Info.plist` | `LSUIElement = true`（不显示 Dock 图标）等 |
| `make_icon.py` | 纯标准库生成 1024px PNG 图标（无第三方依赖） |
| `build.sh` | 生成图标 → 收集 `Sources/**/*.swift` 编译 → 打包 → 签名 → 三项自检 |
| `docs/` | 5 份模块级项目文档（进度环 / 界面与可访问性 / 项目结构 / 作息规则 / 周进度），见 [索引](docs/README.md) |

拆分要点：`main.swift` 曾 1798 行，顶层代码与库代码混放导致全局变量按源码顺序初始化、历史 `--selftest` 因此崩溃；拆分后各文件只放声明、`private` 顶层声明与使用者同文件，`build.sh` 用 `find` 收集全部 `.swift`（Swift 按文件名识别 `main.swift` 为入口，顺序无关）。详见 [项目结构](docs/项目结构.md)。

## 关键实现

> 架构全貌（分层、数据流、生命周期、设计决策）见 [ARCHITECTURE.md](ARCHITECTURE.md)；本节只列实现要点，模块细节见 [docs/](docs/)。

### 菜单栏

| 项 | 说明 |
| --- | --- |
| 宿主 | `NSStatusItem` → `NSStatusBarButton`；`RingStatusView` 作为子视图，`hitTest` 返回 nil 让事件穿透 |
| 三档 | `完整`（带时间）/ `精简`（到分钟，42pt）/ `进度环`（默认，带百分比 58pt、关掉 20pt） |
| 点击 / 高亮 | 系统 button 原生绘制；`NSPopoverDelegate` 调 `button.highlight(true/false)` 保持 |
| 降级 | `ringUnavailable`（button 创建失败）→ SF Symbol 三态图标 |

- 环从 12 点顺时针填充今日净工作进度；状态靠**形态编码**（进度弧 / 满环+中心点 / 虚线空环 / 极淡空心圈），色弱友好。
- 右下角色点四段纯色：0–25% 绿 `#5BAE84`、25–50% 黄 `#DFC25E`、50–75% 橙 `#E0A355`、75–100% 正红 `#FF2D2D`，仅「等下班」显示。
- 百分比 13.5pt 系统常规体、右对齐固定 2pt 边距；描边 `NSColor.controlTextColor` 适配深浅，仅值变化时 `needsDisplay`。
- 绘制参数由纯函数输出：`ringSegments` / `ringDotColor` / `ringDotGeometry` / `menuPercentText`。详见 [菜单栏进度环](docs/菜单栏进度环.md)。

### 设置面板

- `NSPopover`（330×480），4 个 Tab（总览 / 作息 / 周进度 / 显示），低频项进「高级」折叠；底栏固定「立即隐身 / 退出」。
- Cursor 风格：分组标题在卡片外、白底细边框卡片 + `CardSeparator` 行间细线、黑白灰配色。
- `CheckRow` 用系统 `.toggleStyle(.checkbox)`；色板 / 工作日 / 迷你视图均为 `Button` + `.buttonStyle(.plain)`，带 VoiceOver label / value / `.isSelected`。
- `Store.timeError` 统一在 Tab 栏下方渲染可关闭错误横幅。
- `PanelColor` 语义色：白底 `#FFFFFF`（深色 `#1C1C1E`）、卡片 `#F5F5F7`、次要文字 `#6E6E73`，由 `NSColor` dynamicProvider 适配深浅。

### 悬浮窗

- `NSPanel`：`.floating` / `.canJoinAllSpaces` / `.stationary` / `.fullScreenAuxiliary` / `.ignoresCycle`，`isMovableByWindowBackground = true`。
- 与设置面板统一为纯白底 + 细边框（不再用 `.ultraThinMaterial`）；`collapsed` 时变 46×30 迷你视图。
- 语义字体 `.caption / .footnote / .subheadline` + `@ScaledMetric` 跟随 Dynamic Type；高度由 `resizePanelToFit()` 自适应。
- 多显示器：`ensurePanelOnScreen()` 在恢复位置与屏幕参数变化时校验，避免拔掉外接屏后窗口跑丢。

### 时间与状态

- `shifts(around:)` 生成前后班次；`end <= start` 视为次日下班（跨零点）。
- `isWorkday()` 先查 `dayOverrides`（`yyyy-MM-dd` → 1 补班 / 0 放假）再回落每周工作日；午休从净工时扣除。
- `computeState(now, prefs)` 派生 `CountdownState`，是 SwiftUI 视图唯一数据源。
- **周进度**：`weekTargetSeconds` / `weekWorkedSeconds` / `weekProgress` 按「本周累计净工时 ÷ 每周总工时」算进度，目标默认从作息规则自动求和、可手动覆盖；`displayProgress` 按 `progressMode` 给菜单栏环与百分比切换口径，悬浮窗保持当日。详见 [周进度](docs/周进度.md)
- **通用作息规则**：`schedule(for:_:)` 按「当天日期覆盖 > 星期规则 > 全局默认」解析当天作息，`shifts` 与 `nextWorkStart` 都走它。方案库 / 星期规则 / 今天调整全部由用户配置，无任何硬编码时间，详见 [作息规则](docs/作息规则.md)。

### 配色与主题

- 主色固定 `Color.primary`（近黑 / 深色近白）；数字、进度条、百分比、状态点全部单色无渐变，界面不再提供配色自定义。
- `Prefs.palette` / `customHex` 保留只为兼容旧配置，不再暴露 UI。
- `preferredScheme(theme)` 映射 0 跟随 / 1 深色 / 2 浅色。

### 系统能力

| 能力 | 实现 |
| --- | --- |
| 登录自启 | `SMAppService.mainApp.register()`，失败回退 `~/Library/LaunchAgents/com.rumor.offwork-countdown.plist` |
| 状态同步 | `Store.syncLaunchAtLogin()` 启动时 + 每次开面板校正，避免与系统设置脱节 |
| 全局热键 | Carbon `RegisterEventHotKey`（⌃⌥⌘H），无需辅助功能权限 |
| 隐身 | `stealth` / `stealthUntil`；`tick()` 到期自动恢复，手动隐身不跨重启 |
| 单实例 | 启动时检测同名 bundle 已运行则自退 |
| 持久化 | `UserDefaults` 单个 JSON（key `com.rumor.offwork-countdown.prefs.v1`），`Prefs.init(from:)` 用 `decodeIfPresent` 向后兼容；窗口位置一并保存 |
| 自检 | `--version-check` / `--hotkey-check` / `--selftest`（58 项纯函数回归，失败退出非 0），`build.sh` 自动跑三项 |

## 修改默认值

编辑 `Sources/Model/Prefs.swift` 里的 `Prefs` 结构体：

```swift
var start: String = "09:00"
var end: String = "18:00"
var workdays: [Int] = [1, 2, 3, 4, 5]  // 0=周日 ... 6=周六
var showPanel: Bool = true
```

改完重新运行 `./build.sh`。已保存的用户设置会覆盖默认值，如需完全重置可执行
`defaults delete com.rumor.offwork-countdown`（会清除所有个人设置）。
