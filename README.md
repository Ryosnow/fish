# fish

一个 macOS 原生的下班倒数计时器（摸鱼专用 🐟）。

常驻菜单栏 + 可置顶的悬浮小窗。纯 Swift / SwiftUI + AppKit，离线运行、不联网、不上传任何数据。

![早期进度环与四段色点](archive/进度环色点示意.png)

> 上图是历史归档的早期预览。当前界面为黑白灰固定配色、无自定义颜色。

## 快速开始

```bash
git clone https://github.com/Ryosnow/fish.git
cd fish/mac
./build.sh
```

构建产物为仓库根目录的 `下班倒计时.app`，双击即可运行（已 ad-hoc 签名）。**不入库**：`.gitignore` 已忽略 `*.app/` 与 `*.icns`。

**要求**：macOS 13+，Xcode 或 Command Line Tools（`swiftc`、`iconutil`、`sips`、`codesign`、`plutil`）。

## 功能

- **菜单栏进度环**（默认）：14pt 细圆环按今日净工作进度填充，右下角四段纯色色点——0–25% 绿 `#5BAE84`、25–50% 黄 `#DFC25E`、50–75% 橙 `#E0A355`、75–100% 正红 `#FF2D2D`；右侧可选百分比。也可切到「精简」/「完整」文字档
- **悬浮窗**：纯白底、`NSFloatingWindowLevel` + 跨所有桌面空间，全屏应用下也可见；可拖动、位置自动记住、可收缩成 46×30 小图标
- **四种状态**：上班前 / 工作中 / 已下班 / 休息日（显示距下次上班还有多久）
- **作息**：上下班时间、任意工作日、**跨零点班次**、午休不计入进度、**节假日 / 调休按日期覆盖**
- **外观**：黑白灰固定配色（自动适配深浅模式），3 Tab 设置面板（总览 / 作息 / 显示），系统原生复选框
- **隐私**：⌃⌥⌘H 一键隐身（悬浮窗消失、菜单栏只剩极淡空心环），另有「隐身 30 分钟」自动恢复
- 登录时启动（自动与系统设置同步）、下班提示音、透明度

## 操作

| 操作 | 说明 |
| --- | --- |
| 左键点菜单栏 | 打开详情与设置面板 |
| 右键点菜单栏 / 悬浮窗 | 快捷菜单（收缩、隐身、紧凑模式等） |
| `⌃⌥⌘H` | 一键隐身 / 恢复（系统级热键，无需辅助功能权限） |
| 拖动悬浮窗 | 移动位置，重启后保留 |
| 悬浮窗右上角 `−` | 收缩成小图标，点一下展开 |

## 目录

| 路径 | 说明 |
| --- | --- |
| `mac/Sources/` | 14 个按职责分层的 Swift 文件；`main.swift` 只放启动入口与 CLI 分支 |
| [mac/ARCHITECTURE.md](mac/ARCHITECTURE.md) | **项目架构**：分层、数据流、生命周期、设计决策、技术债 |
| [mac/README.md](mac/README.md) | 源码说明：构建、目录、逐模块实现、改默认值 |
| [mac/CHANGELOG.md](mac/CHANGELOG.md) | 版本与时间线 |
| `mac/Info.plist` | 应用配置（`LSUIElement`，不显示 Dock 图标） |
| `mac/build.sh` | 生成图标 → 收集全部 `.swift` 编译 → 打包 → ad-hoc 签名 → 自检 |
| `mac/make_icon.py` | 纯 Python 标准库生成 App 图标 |
| `mac/docs/` | 3 份模块级项目文档（进度环 / 界面与可访问性 / 项目结构）+ [索引](mac/docs/README.md) |
| `archive/` | 早期网页版与旧配色预览，非当前交付物 |

## 自检

`build.sh` 会自动运行三项：

```bash
./下班倒计时.app/Contents/MacOS/OffWorkCountdown --version-check
./下班倒计时.app/Contents/MacOS/OffWorkCountdown --hotkey-check
./下班倒计时.app/Contents/MacOS/OffWorkCountdown --selftest   # 38 项纯函数回归测试
```

覆盖跨零点 / 午休 / 调休 / 跨周末 / 周五下班 / 进度环形态 / 色点四档与边界 / 菜单栏百分比 / 登录自启状态同步 / 旧配置兼容等，失败直接退出非 0。

## 备注

- 设置保存在 `UserDefaults`（`com.rumor.offwork-countdown`）的单个 JSON，新增字段对旧配置向后兼容
- 应用不联网，**法定节假日与调休日期需在设置里逐日手动标记**（不内置未经核实的数据）
- 移动 `.app` 后请把「登录时启动」关掉再打开一次以刷新路径
- 本人私有项目，许可见 [mac/LICENSE](mac/LICENSE)（未选开源协议）
