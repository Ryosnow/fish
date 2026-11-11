# 更新日志

按时间倒序记录。`Info.plist` 的 `CFBundleShortVersionString` 当前为 **1.0**；这是个人小工具，不做语义化版本发布，改动以日期归档。模块级文档见 [docs/](docs/)，当前架构见 [ARCHITECTURE.md](ARCHITECTURE.md)。

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
