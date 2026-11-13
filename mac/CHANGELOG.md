# 更新日志

按时间倒序记录。`Info.plist` 的 `CFBundleShortVersionString` 当前为 **1.0**；这是个人小工具，不做语义化版本发布，改动以日期归档。模块级文档见 [docs/](docs/)，当前架构见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 2026-11-13

### 修复
- 作息 Tab「上下班时间」行：`Text("上班")` / `Text("下班")` 曾被 HStack 压缩成竖排（看起来像乱码、挤占页面），改为两行布局 + `.lineLimit(1).fixedSize()`。
- 所有 `DatePicker` 去掉强制 `.frame(width:)`，改用 `.fixedSize()` 保留内在宽度，避免时间/日期字段被裁切。
- 设置面板高度 420pt → 480pt，适配两行布局与新增卡片后两个 Tab 都不需滚动。

### 新增：周进度（当日 / 本周口径切换）
- 新增第 4 个 Tab「周进度」：口径分段控件、每周总工时（自动求和 / 手动固定 Stepper）、本周累计净工时 / 目标 / 剩余 / 进度条。
- `weekTargetSeconds` / `weekWorkedSeconds` / `weekProgress` / `displayProgress` 四个纯函数；周目标默认从本周作息规则自动求和，允许手动覆盖。
- 菜单栏圆环与百分比可在两种口径切换：周模式环改为纯周进度弧、百分比 1 位小数、项宽 58→68pt；右键菜单可一键切换；悬浮窗保持当日进度不变。
- 纯函数自测 46 → 58 项；详见 [周进度](docs/周进度.md)。

### 新增：通用作息规则
- 做成**零硬编码时间、零预设星期**的配置化机制，任何人都能按自己的班表配置（否决了写死「周五 17:30」等个人化快捷按钮的方案）。
- `WorkSchedule`（命名方案，纯模板）+ 三类绑定规则：全局默认 / 星期规则 / 日期覆盖；优先级「日期 > 星期 > 默认」，与现有补班 / 放假正交。
- 界面：「作息」Tab 新增「作息方案」「每周规则」（默认折叠），总览 Tab 新增「今天下班时间」（默认收起，标题行显示当前下班时间；展开后可调整）。
- 旧配置无新字段 → 解码为空，行为完全不变；纯函数自测 38 → 46 项。详见 [作息规则](docs/作息规则.md)。

## 2026-11-11

### 结构与工程
- `main.swift`（1798 行）拆为 14 个按职责分层的 Swift 文件（`App/` / `Model/` / `MenuBar/` / `UI/` / `Tests/`）；`build.sh` 改为 `find Sources -name '*.swift'` 收集全部文件编译。顶层可执行代码只留在 `main.swift`，根除全局变量按源码顺序初始化导致的 `--selftest` segfault。
- 新增 [ARCHITECTURE.md](ARCHITECTURE.md)、[CHANGELOG.md](CHANGELOG.md)、LICENSE；README「关键实现」重写为结构化小节；3 份设计文档标注为历史决策记录。
- 归档早期网页版与旧色点预览到 `../archive/`。

### 界面
- 设置面板按 Cursor / macOS 系统设置风格重做：分组标题在卡片外、白底细边框卡片、行间细线、黑白灰配色、每 Tab 大标题。
- 所有开关改为系统复选框（`CheckRow`），取消蓝色胶囊 `.switch`。
- 取消配色自定义：主色固定 `Color.primary`，语义色 `PanelColor` 提供浅/深两套值；数字、进度条、百分比、状态点全部单色无渐变。
- 悬浮窗与设置面板统一为纯白底（不再用 `.ultraThinMaterial`）；小字改语义字体 + `@ScaledMetric` 支持 Dynamic Type；收缩态 emoji 换 `clock` SF Symbol。

### 修复
- `Store.timeError` 改为跨 Tab 统一可关闭错误横幅（此前登录自启失败在「显示」Tab 看不到反馈）。
- 色板 / 工作日按钮 / 迷你视图由 `onTapGesture` 改为 `Button` + `.buttonStyle(.plain)`，补 VoiceOver label / value / `.isSelected`。
- `Store.syncLaunchAtLogin()` 启动时与每次打开面板校正登录自启开关，与系统设置真实状态同步。
- 纯函数自测 37 → **38 项**（新增登录自启状态同步断言）。

## 2026-11-10

- 菜单栏新增「进度环」档：自绘细圆环 + 右下四段阶段色点 + 右侧百分比；环从 12 点顺时针填充净工作进度，状态靠形态编码（色弱友好）。
- 点击高亮回归系统原生 `NSStatusBarButton`（`RingStatusView` 作为子视图、`hitTest` 穿透），删掉自绘高亮与 `mouseDown` 接管，编译废弃警告消失。
- 时间模型完善：跨零点班次、午休扣除净工时、节假日 / 调休按日期覆盖、周五下班后跨周末倒数修正。
- 配色经历多轮迭代（低饱和预设 → apple.com 风格 → 系统强调色 → 最终固定黑白灰）。
- 设置面板收敛为 3 个 Tab + 分组卡片 + 「高级」折叠（渐进式披露）。

## 2026-11-02 ~ 11-05

- 从早期 HTML 网页版改为 macOS 原生菜单栏应用：`LSUIElement`（无 Dock 图标）、悬浮窗、隐身 / 收缩、全局热键 ⌃⌥⌘H、单实例、`UserDefaults` 持久化。
- 早期网页版保留在 `../archive/下班倒数计时器.html`，可在别的电脑当备用。
