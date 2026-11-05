# fish

一个 macOS 原生的下班倒数计时器（摸鱼专用 🐟）。

常驻顶部菜单栏 + 一个永远置顶、可拖动的悬浮小窗。纯 Swift / SwiftUI + AppKit，离线运行、不联网、不上传任何数据。

## 快速开始

```bash
git clone https://github.com/Ryosnow/fish.git
cd fish/mac
./build.sh
```

构建完成后在仓库根目录生成 `下班倒计时.app`，双击即可运行（已 ad-hoc 签名）。

**要求**：macOS 13+，Xcode 或 Command Line Tools（`swiftc`、`iconutil`、`sips`、`codesign`、`plutil`）。

## 功能

- 菜单栏实时倒计时；休息日 / 下班后自动切换文案
- 悬浮窗：`NSFloatingWindowLevel` + 跨所有桌面空间，全屏应用下也可见，可拖动、位置自动记住
- 四种状态：上班前 / 工作中 / 下班后 / 休息日，配进度条与摸鱼语录
- 设置：上下班时间、工作日、紧凑模式、总在最前、下班提示音、登录时启动、外观、透明度
- 配色：5 套低饱和预设（默认「雾蓝」）+ 跟随系统强调色 + 自定义取色器
- 怕被看到时：
  - 悬浮窗右上角 `−` 收缩成 46×30 的小图标，**不显示任何数字**
  - `⌃⌥⌘H` 一键完全隐身（悬浮窗消失、菜单栏只剩一个灰色时钟），再按恢复
  - 右键菜单 / 设置里还有「隐身 30 分钟」，到期自动恢复

## 操作

| 操作 | 说明 |
| --- | --- |
| 左键点菜单栏 | 打开详情与设置面板 |
| 右键点菜单栏 / 悬浮窗 | 快捷菜单（收缩、隐身、紧凑模式等） |
| `⌃⌥⌘H` | 全局热键：一键隐身 / 恢复，无需辅助功能权限 |
| 拖动悬浮窗 | 移动位置，重启后保留 |
| 悬浮窗右上角 `−` | 收缩成小图标；点小图标展开 |

## 目录

| 路径 | 说明 |
| --- | --- |
| `mac/Sources/main.swift` | 全部逻辑：状态计算、菜单栏、悬浮窗、设置、配色、隐身 |
| `mac/Info.plist` | 应用配置（`LSUIElement`，不显示 Dock 图标） |
| `mac/build.sh` | 生成图标 → 编译 → 打包 → ad-hoc 签名 → 自检 |
| `mac/make_icon.py` | 纯 Python 标准库生成 App 图标，无第三方依赖 |

设置保存在 `UserDefaults`（`com.rumor.offwork-countdown`），改动即时生效；新增字段对旧配置向后兼容。

## 构建自检

```bash
./下班倒计时.app/Contents/MacOS/OffWorkCountdown --version-check
./下班倒计时.app/Contents/MacOS/OffWorkCountdown --hotkey-check
```

`build.sh` 会自动运行这两项。

## 备注

- 暂不支持跨零点排班（如 22:00 上班、次日 06:00 下班），设置面板会拦截。
- 「登录时启动」优先用 `SMAppService`，失败时回退写 LaunchAgent；移动 `.app` 后重新开关一次即可刷新路径。
