# 项目文档索引

本目录放**描述当前实现的模块级项目文档**（不是历史计划）。改动代码时请同步更新对应文档。

| 文档 | 主题 | 对应源码 |
| --- | --- | --- |
| [菜单栏进度环](菜单栏进度环.md) | 环的形态映射、四段色点、右侧百分比、系统 `NSStatusBarButton` 高亮与降级 | `Sources/MenuBar/`、`Sources/App/AppDelegate.swift` |
| [界面与可访问性](界面与可访问性.md) | 黑白灰语义色、3 Tab 设置面板、系统复选框、悬浮窗白底、Dynamic Type、登录自启状态同步 | `Sources/UI/`、`Sources/App/Store.swift` |
| [项目结构](项目结构.md) | 14 个 Swift 文件的分层、依赖规则、`main.swift` 顶层代码规则、构建与持久化 | `Sources/`、`build.sh` |
| [作息规则](作息规则.md) | 通用配置化作息：方案库、星期规则、当天临时调整与优先级 | `Sources/Model/`、`Sources/UI/MenuView.swift` |
| [周进度](周进度.md) | 当日 / 本周进度口径切换、周工时自动求和与手动覆盖（**已定稿设计，待实现**） | `Sources/Model/Time.swift`、`Sources/MenuBar/Ring.swift` |

## 文档体系

| 场景 | 文档 |
| --- | --- |
| 架构总览（分层、数据流、生命周期、设计决策、技术债） | [ARCHITECTURE.md](../ARCHITECTURE.md) |
| 构建命令、目录、逐模块实现要点、改默认值 | [README.md](../README.md) |
| 模块级实现细节 | 本目录 3 份文档 |
| 版本与时间线 | [CHANGELOG.md](../CHANGELOG.md) |
| 使用说明、快捷键 | [Obsidian 笔记](../../下班倒数计时器.md) |

早期按日期命名的设计计划（`-design.md`）已整合进上述文档与 `ARCHITECTURE.md §13` 的设计决策记录，不再单独保留；时间线由 `CHANGELOG.md` 承担。
