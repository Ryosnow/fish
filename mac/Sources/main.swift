import AppKit
import SwiftUI
import Combine
import ServiceManagement
import Carbon

// 全局热键：⌃⌥⌘H，任何应用前台都能一键隐身 / 恢复（不需要辅助功能权限）
private var globalHotKeyAction: (() -> Void)?
private var hotKeyRef: EventHotKeyRef?
private var eventHandlerRef: EventHandlerRef?

func registerGlobalHotKey(_ action: @escaping () -> Void) -> OSStatus {
    globalHotKeyAction = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
        DispatchQueue.main.async { globalHotKeyAction?() }
        return noErr
    }, 1, &spec, nil, &eventHandlerRef)
    guard installed == noErr else { return installed }
    let id = EventHotKeyID(signature: OSType(0x4F574348), id: 1) // 'OWCH'
    return RegisterEventHotKey(UInt32(kVK_ANSI_H),
                               UInt32(controlKey | optionKey | cmdKey),
                               id, GetApplicationEventTarget(), 0, &hotKeyRef)
}

// 构建自检：不创建 UI，用于验证可执行文件、动态库与热键注册
if CommandLine.arguments.contains("--version-check") {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    print("OffWorkCountdown 1.0 | macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) | OK")
    exit(0)
}
if CommandLine.arguments.contains("--hotkey-check") {
    let status = registerGlobalHotKey({})
    print("hotkey register status: \(status) (\(status == noErr ? "OK" : "conflict or unavailable"))")
    exit(0)
}
// 注意：--selftest 放在文件末尾（所有顶层全局常量之后）执行，
// 因为 main.swift 中的全局变量按源码顺序初始化。

// MARK: - 偏好设置

struct Prefs: Codable {
    var start: String = "09:00"            // 上班时间 HH:mm
    var end: String = "18:00"              // 下班时间 HH:mm
    var workdays: [Int] = [1, 2, 3, 4, 5] // 0=周日 ... 6=周六
    var showPanel: Bool = true             // 悬浮窗
    var compact: Bool = false              // 紧凑模式
    var alwaysOnTop: Bool = true           // 总在最前
    var sound: Bool = true                 // 下班提示音
    var theme: Int = 0                    // 0 跟随系统 / 1 深色 / 2 浅色
    var launchAtLogin: Bool = false        // 登录时启动
    var panelOpacity: Double = 0.94
    var panelOrigin: [Double]? = nil       // 记住窗口位置
    var palette: Int = 0                  // 配色：0-4 预设 / 5 系统 / 6 自定义
    var customHex: String = "#7C93A8"     // 自定义主色
    var collapsed: Bool = false           // 悬浮窗收缩成小图标
    var stealth: Bool = false             // 完全隐身
    var stealthUntil: Double? = nil       // 临时隐身到期时间
    var breakEnabled: Bool = false        // 午休不计入工作进度
    var breakStart: String? = "12:00"
    var breakEnd: String? = "13:00"
    var dayOverrides: [String: Int] = [:] // "yyyy-MM-dd": 1 补班 / 0 放假
    var menuStyle: Int = 2               // 菜单栏：0 完整 / 1 精简 / 2 三态图标（默认）

    private enum CodingKeys: String, CodingKey {
        case start, end, workdays, showPanel, compact, alwaysOnTop, sound, theme,
             launchAtLogin, panelOpacity, panelOrigin, palette, customHex,
             collapsed, stealth, stealthUntil, breakEnabled, breakStart, breakEnd,
             dayOverrides, menuStyle
    }

    init() {}

    // 自定义解码，保证旧版本保存的设置里没有新字段时也能正常读取
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? "09:00"
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? "18:00"
        workdays = try c.decodeIfPresent([Int].self, forKey: .workdays) ?? [1, 2, 3, 4, 5]
        showPanel = try c.decodeIfPresent(Bool.self, forKey: .showPanel) ?? true
        compact = try c.decodeIfPresent(Bool.self, forKey: .compact) ?? false
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        theme = try c.decodeIfPresent(Int.self, forKey: .theme) ?? 0
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        panelOpacity = try c.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? 0.94
        panelOrigin = try c.decodeIfPresent([Double].self, forKey: .panelOrigin)
        palette = try c.decodeIfPresent(Int.self, forKey: .palette) ?? 0
        customHex = try c.decodeIfPresent(String.self, forKey: .customHex) ?? "#7C93A8"
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        stealth = try c.decodeIfPresent(Bool.self, forKey: .stealth) ?? false
        stealthUntil = try c.decodeIfPresent(Double.self, forKey: .stealthUntil)
        breakEnabled = try c.decodeIfPresent(Bool.self, forKey: .breakEnabled) ?? false
        breakStart = try c.decodeIfPresent(String.self, forKey: .breakStart) ?? "12:00"
        breakEnd = try c.decodeIfPresent(String.self, forKey: .breakEnd) ?? "13:00"
        dayOverrides = try c.decodeIfPresent([String: Int].self, forKey: .dayOverrides) ?? [:]
        menuStyle = try c.decodeIfPresent(Int.self, forKey: .menuStyle) ?? 2
    }

    func validated() -> Prefs {
        var p = self
        // end <= start 是合法的跨零点班次，不再重置
        func mins(_ s: String) -> Int { let t = hhmm(s); return t.0 * 60 + t.1 }
        if p.start.isEmpty || p.end.isEmpty { p.start = "09:00"; p.end = "18:00" }
        p.workdays = Array(Set(p.workdays.filter { $0 >= 0 && $0 <= 6 })).sorted()
        p.panelOpacity = min(max(p.panelOpacity, 0.4), 1.0)
        if p.theme < 0 || p.theme > 2 { p.theme = 0 }
        if p.palette < 0 || p.palette > 6 { p.palette = 0 }
        p.customHex = RGB(hex: p.customHex).hex
        let b1 = hhmm(p.breakStart ?? "12:00"), b2 = hhmm(p.breakEnd ?? "13:00")
        if b1.0 * 60 + b1.1 >= b2.0 * 60 + b2.1 { p.breakStart = "12:00"; p.breakEnd = "13:00" }
        p.dayOverrides = p.dayOverrides.filter { $0.key.count == 10 && ($0.value == 0 || $0.value == 1) }
        if p.menuStyle < 0 || p.menuStyle > 2 { p.menuStyle = 2 }
        return p
    }
}

// MARK: - 时间小工具

func hhmm(_ s: String) -> (Int, Int) {
    let parts = s.split(separator: ":").map { Int($0) ?? 0 }
    let h = parts.count > 0 ? min(max(parts[0], 0), 23) : 9
    let m = parts.count > 1 ? min(max(parts[1], 0), 59) : 0
    return (h, m)
}

func isCrossMidnight(_ p: Prefs) -> Bool {
    let a = hhmm(p.start), b = hhmm(p.end)
    return a.0 * 60 + a.1 >= b.0 * 60 + b.1
}

func hhmmString(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
}

func dateFromHHMM(_ s: String) -> Date {
    let (h, m) = hhmm(s)
    let cal = Calendar.current
    var c = cal.dateComponents([.year, .month, .day], from: Date())
    c.hour = h; c.minute = m; c.second = 0
    return cal.date(from: c) ?? Date()
}

func dateAt(_ s: String, on day: Date) -> Date {
    let (h, m) = hhmm(s)
    let cal = Calendar.current
    var c = cal.dateComponents([.year, .month, .day], from: day)
    c.hour = h; c.minute = m; c.second = 0
    return cal.date(from: c) ?? day
}

func digits(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}

/// 菜单栏精简格式：只到分钟并去掉小时前导 0（02:32:30 → 2:32）
func shortMinutes(_ s: String) -> String {
    let parts = s.split(separator: ":").map(String.init)
    guard parts.count == 3 else { return s }
    var h = parts[0]
    while h.count > 1 && h.hasPrefix("0") { h.removeFirst() }
    return h + ":" + parts[1]
}

func human(_ t: TimeInterval) -> String {
    let mins = max(0, Int(t / 60))
    let h = mins / 60, m = mins % 60
    return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
}

func pick(_ arr: [String], _ now: Date) -> String {
    guard !arr.isEmpty else { return "" }
    return arr[Int(now.timeIntervalSince1970 / 60) % arr.count]
}

// MARK: - 状态计算

enum Phase: Equatable { case before, working, off, rest }

struct CountdownState {
    var phase: Phase
    var title: String
    var label: String
    var digits: String
    var progress: Double
    var sub: String
    var quote: String
    var menu: String       // 完整菜单栏文案
    var menuShort: String  // 精简菜单栏文案
}

private let QUOTES: [String: [String]] = [
    "rest": ["今天不用上班，睡到自然醒才是正经事 🛌", "休息日请勿打开工作群，违者罚款一顿火锅 🍲", "把「下班」两个字从字典里删掉，今天全天都是你的 🌈", "出门走走吧，太阳不会等你开完会 ☀️"],
    "before": ["还没到上班时间，慢慢喝完这杯咖啡 ☕", "通勤路上的每一分钟，都算在人生里 🚇", "早到不如巧到，先看看今天天气 ☁️"],
    "far": ["路还很长，先给自己泡杯茶 🍵", "别急，上午会过完的，下午也会过完的 ⏳", "把最难的需求留到「明天再说」，是古老的智慧 📜", "今天的 KPI 是：平安活到下班 🐟"],
    "mid": ["过半了！下午的太阳比较温柔 🌤️", "伸个懒腰，颈椎比你更想下班 🦴", "此刻适合站起来接杯水，顺便巡逻一下茶水间 🚶", "再撑一会儿，胜利在望 💪"],
    "hour": ["最后一小时，别开新需求了 ⚠️", "收尾时间：提交、保存、写日报 📝", "开始整理桌面，物理和心理上的都要 🧹"],
    "minutes": ["十分钟倒计时，关掉多余的标签页 🖥️", "把包放在最顺手的位置 🎒", "电梯在等你，别让电梯等太久 🛗"],
    "final": ["站起来！拿包！走人！🚪", "最后 60 秒，祝一路绿灯 🚦", "保存，提交，关机，一气呵成 💾"],
    "off": ["今天辛苦了，快溜！🏃", "下班不积极，思想有问题 😌", "工作消息已进入「明天再说」模式 📴", "今晚属于你自己，去吃点好的 🍜"],
    "late": ["都这个点了，该睡了 😴 明天还要上班呢"]
]

// MARK: - 日历覆盖（节假日 / 调休）与班次区间

func dayKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
}

/// 覆盖表优先：1 = 补班 / 0 = 放假；否则按每周工作日
func isWorkday(_ day: Date, _ p: Prefs) -> Bool {
    if let override = p.dayOverrides[dayKey(day)] { return override == 1 }
    return p.workdays.contains(Calendar.current.component(.weekday, from: day) - 1)
}

struct Shift {
    var day: Date
    var start: Date
    var end: Date
    var breakStart: Date?
    var breakEnd: Date?

    var breakLength: TimeInterval {
        guard let b = breakStart, let e = breakEnd else { return 0 }
        return e.timeIntervalSince(b)
    }
    var totalWork: TimeInterval { end.timeIntervalSince(start) - breakLength }
    func breakElapsed(at now: Date) -> TimeInterval {
        guard let b = breakStart, let e = breakEnd else { return 0 }
        if now <= b { return 0 }
        if now >= e { return breakLength }
        return now.timeIntervalSince(b)
    }
    func inBreak(_ now: Date) -> Bool {
        guard let b = breakStart, let e = breakEnd else { return false }
        return now >= b && now < e
    }
}

/// now 前后各两天的工作日班次；end <= start 时视为次日下班（跨零点）
func shifts(around now: Date, _ p: Prefs) -> [Shift] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    var result: [Shift] = []
    for offset in -2...2 {
        guard let day = cal.date(byAdding: .day, value: offset, to: today),
              isWorkday(day, p) else { continue }
        let s = dateAt(p.start, on: day)
        var e = dateAt(p.end, on: day)
        if e <= s { e = cal.date(byAdding: .day, value: 1, to: e) ?? e }

        var bs: Date? = nil, be: Date? = nil
        if p.breakEnabled {
            // 把午休时间对齐到班次内部（跨零点班次的午休可能落在凌晨）
            func align(_ t: Date, after anchor: Date) -> Date {
                var t = t
                while t < anchor { t = cal.date(byAdding: .day, value: 1, to: t) ?? t }
                return t
            }
            let raw1 = dateAt(p.breakStart ?? "12:00", on: day)
            let b1 = align(raw1, after: s)
            let b2 = align(dateAt(p.breakEnd ?? "13:00", on: day), after: b1)
            if b1 >= s && b2 > b1 && b2 <= e { bs = b1; be = b2 }
        }
        result.append(Shift(day: day, start: s, end: e, breakStart: bs, breakEnd: be))
    }
    return result.sorted { $0.start < $1.start }
}

func nextWorkStart(_ now: Date, _ p: Prefs) -> Date? {
    let cal = Calendar.current
    for i in 0...14 {
        guard let day = cal.date(byAdding: .day, value: i, to: now),
              isWorkday(day, p) else { continue }
        let s = dateAt(p.start, on: day)
        if s > now { return s }
    }
    return nil
}

func workdaysThisWeek(_ now: Date, _ p: Prefs) -> Int {
    let cal = Calendar.current
    let offset = (cal.component(.weekday, from: now) + 5) % 7 // 距周一
    var n = 0
    for i in 0..<(7 - offset) {
        guard let d = cal.date(byAdding: .day, value: i, to: now) else { continue }
        if isWorkday(d, p) { n += 1 }
    }
    return n
}

func workingQuote(_ remain: TimeInterval, _ now: Date) -> String {
    if remain >= 4 * 3600 { return pick(QUOTES["far"]!, now) }
    if remain >= 2 * 3600 { return pick(QUOTES["mid"]!, now) }
    if remain >= 3600 { return pick(QUOTES["hour"]!, now) }
    if remain >= 600 { return pick(QUOTES["minutes"]!, now) }
    return pick(QUOTES["final"]!, now)
}

func computeState(_ now: Date, _ p: Prefs) -> CountdownState {
    let cal = Calendar.current
    let weekdayCN = ["日", "一", "二", "三", "四", "五", "六"]
    let all = shifts(around: now, p)
    let nxt = nextWorkStart(now, p)

    func nextStartText(_ n: Date?) -> String {
        guard let n else { return "没有排班" }
        let c = cal.dateComponents([.month, .day, .weekday], from: n)
        return "\(c.month ?? 1) 月 \(c.day ?? 1) 日（周\(weekdayCN[(c.weekday ?? 1) - 1])）\(hhmmString(n))"
    }

    // 1. 正在班上（含跨零点班次）
    if let sh = all.first(where: { now >= $0.start && now < $0.end }) {
        let remain = sh.end.timeIntervalSince(now)
        let elapsed: Double = now.timeIntervalSince(sh.start) - sh.breakElapsed(at: now)
        let total: Double = sh.totalWork
        var progress: Double = 0
        if total > 0 {
            progress = elapsed / total
            if progress < 0 { progress = 0 }
            if progress > 1 { progress = 1 }
        }
        let onBreak = sh.inBreak(now)
        return CountdownState(
            phase: .working, title: onBreak ? "午休中 🍚" : "摸鱼进行中 🐟",
            label: "距离下班还有", digits: digits(remain), progress: progress,
            sub: "已工作 \(human(elapsed)) · 今日共 \(human(total))" + (p.breakEnabled ? "（已扣午休）" : ""),
            quote: onBreak ? "午休中，先别看倒计时 🍚" : workingQuote(remain, now),
            menu: onBreak ? "🍚 午休中" : "🕕 \(digits(remain))",
            menuShort: onBreak ? "午休" : shortMinutes(digits(remain)))
    }

    let lastEnd = all.filter { $0.end <= now }.map { $0.end }.max()
    // 「下次上班」用 nextWorkStart（最长 14 天），不能用 shifts 的 ±2 天候选：
    // 否则周五下班跨周末时找不到下次上班，会误判成「今天不用上班」
    let nextStart = nxt

    // 2. 刚下班（跨零点班次结束后也算）
    if let le = lastEnd, let ns = nextStart,
       now.timeIntervalSince(le) < 12 * 3600,
       now.timeIntervalSince(le) <= ns.timeIntervalSince(now) {
        let off = now.timeIntervalSince(le)
        return CountdownState(
            phase: .off, title: "下班啦！🎉", label: "已经下班",
            digits: digits(off), progress: 1,
            sub: "今日任务已结束 · 下次上班 " + nextStartText(nxt) + " · 快回家吧",
            quote: off > 4 * 3600 ? QUOTES["late"]![0] : pick(QUOTES["off"]!, now),
            menu: "✅ 下班啦", menuShort: "下班")
    }

    // 3. 休息日（含被标记为「放假」的工作日）
    if !isWorkday(cal.startOfDay(for: now), p) {
        return CountdownState(
            phase: .rest, title: "今天不用上班 🎉",
            label: nxt == nil ? "永远不用上班" : "距离下次上班还有",
            digits: nxt.map { digits($0.timeIntervalSince(now)) } ?? "--:--:--",
            progress: 0,
            sub: nxt.map { _ in "下次上班：" + nextStartText(nxt) } ?? "你把所有工作日都取消了，恭喜 🎊",
            quote: pick(QUOTES["rest"]!, now), menu: "🎉 休息日", menuShort: "休息")
    }

    // 4. 上班前
    if let ns = nextStart {
        return CountdownState(
            phase: .before, title: "还没上班，先别急 ☕", label: "距离上班还有",
            digits: digits(ns.timeIntervalSince(now)), progress: 0,
            sub: "今天 \(hhmmString(ns)) 上班 · 本周共 \(workdaysThisWeek(now, p)) 个工作日",
            quote: pick(QUOTES["before"]!, now),
            menu: "☕ \(hhmmString(ns)) 上班",
            menuShort: shortMinutes(digits(ns.timeIntervalSince(now))))
    }

    // 兜底
    return CountdownState(
        phase: .rest, title: "今天不用上班 🎉", label: "距离下次上班还有",
        digits: nxt.map { digits($0.timeIntervalSince(now)) } ?? "--:--:--",
        progress: 0, sub: nxt.map { _ in "下次上班：" + nextStartText(nxt) } ?? "没有排班",
        quote: pick(QUOTES["rest"]!, now), menu: "🎉 休息日", menuShort: "休息")
}

/// 菜单栏三态图标：全部用填充型 SF Symbol，单色模板渲染、跟随菜单栏明暗
/// 填充图形比线框符号更饱满，小尺寸下辨识度更高、周围不显得空
func statusIconName(_ phase: Phase) -> String {
    switch phase {
    case .before, .working: return "clock.fill"            // 还在上班 / 等下班
    case .off:              return "checkmark.circle.fill" // 已下班
    case .rest:             return "moon.fill"             // 休息日
    }
}

// MARK: - 菜单栏进度环

/// 右下角进度阶段色点（低饱和 RGB，0...1）
struct RingDot: Equatable {
    var r: Double, g: Double, b: Double
}

/// 四段纯色，到边界直接切换；只在「等下班」阶段显示
func ringDotColor(phase: Phase, progress: Double, isStealth: Bool) -> RingDot? {
    guard !isStealth, (phase == .working || phase == .before) else { return nil }
    let green  = RingDot(r: 0.357, g: 0.682, b: 0.518) // #5BAE84
    let yellow = RingDot(r: 0.875, g: 0.761, b: 0.369) // #DFC25E
    let orange = RingDot(r: 0.878, g: 0.639, b: 0.333) // #E0A355
    let red    = RingDot(r: 0.851, g: 0.439, b: 0.420) // #D9706B
    let p = min(max(progress, 0), 1)
    if p < 0.25 { return green  }   // 0–25%   绿
    if p < 0.50 { return yellow }   // 25–50%  黄
    if p < 0.75 { return orange }   // 50–75%  橙
    return red                      // 75–100% 红
}

/// 色点几何：右下角、稍微压住环的一小段（纯函数，便于自测越界）
struct RingDotGeometry {
    var center: CGPoint
    var radius: CGFloat
}

func ringDotGeometry(ringCenter: CGPoint, ringRadius: CGFloat) -> RingDotGeometry {
    let angle = -CGFloat.pi / 4
    let dist = ringRadius + 1.5   // 比原来更贴近环，让色点盖住环右下角一点
    return RingDotGeometry(
        center: CGPoint(x: ringCenter.x + dist * cos(angle),
                        y: ringCenter.y + dist * sin(angle)),
        radius: 3.0)             // 直径 6pt（原 4.4pt）
}

/// 绘制参数（纯数据，便于自测）
struct RingSpec {
    var baseAlpha: Double   // 底环透明度
    var progress: Double    // clamp 后的进度 0...1
    var dashed: Bool        // 休息日虚线环
    var filled: Bool        // 是否画实色弧（含满环）
    var centerDot: Bool     // 已下班的中心完成点
}

func ringSegments(phase: Phase, progress: Double, isStealth: Bool) -> RingSpec {
    let p = min(max(progress, 0), 1)
    if isStealth {
        return RingSpec(baseAlpha: 0.10, progress: 0, dashed: false, filled: false, centerDot: false)
    }
    switch phase {
    case .before, .working:
        return RingSpec(baseAlpha: 0.20, progress: p, dashed: false, filled: true, centerDot: false)
    case .off:
        return RingSpec(baseAlpha: 0.20, progress: 1, dashed: false, filled: true, centerDot: true)
    case .rest:
        return RingSpec(baseAlpha: 0, progress: 0, dashed: true, filled: false, centerDot: false)
    }
}

/// 菜单栏自绘进度环：14pt 细环，按今日进度填充，不显示任何数字
final class RingStatusView: NSView {
    var phase: Phase = .working
    var progress: Double = 0
    var isStealth = false
    var isBreak = false
    private var pressed = false

    weak var actionTarget: AnyObject?
    var leftAction: Selector?
    var rightAction: Selector?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let spec = ringSegments(phase: phase, progress: progress, isStealth: isStealth)
        let color = NSColor.controlTextColor   // 自动适配深浅模式
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r: CGFloat = 7
        let lw: CGFloat = 2

        // 点击高亮：一层很淡的圆角底，替代显眼的系统蓝块
        if pressed {
            color.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        if spec.baseAlpha > 0 {
            ctx.setStrokeColor(color.withAlphaComponent(spec.baseAlpha).cgColor)
            ctx.setLineWidth(lw)
            ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            ctx.strokePath()
        }

        if spec.dashed {
            ctx.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.butt)
            for i in 0..<8 {
                let a0 = CGFloat.pi / 2 - CGFloat(i) * .pi / 4 - 0.12
                ctx.addArc(center: c, radius: r, startAngle: a0, endAngle: a0 - 0.42, clockwise: true)
                ctx.strokePath()
            }
        } else if spec.filled {
            ctx.setStrokeColor(color.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            let start = CGFloat.pi / 2
            let end = start - 2 * .pi * CGFloat(spec.progress)
            ctx.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: true)
            ctx.strokePath()
            if isBreak {
                // 午休：弧末端加一个小圆点表示暂停
                let p = CGPoint(x: c.x + r * cos(end), y: c.y + r * sin(end))
                color.withAlphaComponent(0.95).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)).fill()
            }
        }

        if spec.centerDot {
            color.withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)).fill()
        }

        // 右下角进度阶段色点（绿 → 橙 → 红），最后绘制以盖住环的一小段
        if let dot = ringDotColor(phase: phase, progress: progress, isStealth: isStealth) {
            let geo = ringDotGeometry(ringCenter: c, ringRadius: r)
            let rad = geo.radius
            NSColor(red: CGFloat(dot.r), green: CGFloat(dot.g),
                    blue: CGFloat(dot.b), alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: geo.center.x - rad, y: geo.center.y - rad,
                                        width: rad * 2, height: rad * 2)).fill()
        }
    }

    // 自绘 view 没有系统按钮行为，需自己接管点击
    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
        if let t = actionTarget, let a = leftAction { NSApp.sendAction(a, to: t, from: self) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pressed = false
            self?.needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if let t = actionTarget, let a = rightAction { NSApp.sendAction(a, to: t, from: self) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 纯函数回归自测（--selftest）

func runSelfTest() {
    let cal = Calendar.current
    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.calendar = cal; c.timeZone = cal.timeZone
        c.year = y; c.month = m; c.day = day; c.hour = h; c.minute = mi; c.second = s
        return cal.date(from: c)!
    }
    func cfg(_ modify: (inout Prefs) -> Void = { _ in }) -> Prefs {
        var x = Prefs(); modify(&x); return x.validated()
    }
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(name) \(detail)") }
        else { print("  ✗ \(name) \(detail)"); failures += 1 }
    }

    let a = computeState(d(2026, 11, 2, 15, 27, 30), cfg()) // 周一
    check("工作日倒计时", a.phase == .working && a.digits == "02:32:30", a.digits)
    check("工作日进度", abs(a.progress - 0.7176) < 0.002, String(format: "%.4f", a.progress))

    let b = computeState(d(2026, 11, 1, 11, 0), cfg()) // 周日
    check("休息日", b.phase == .rest && b.digits == "22:00:00", b.digits)

    let c = computeState(d(2026, 11, 2, 8, 0), cfg())
    check("上班前", c.phase == .before && c.digits == "01:00:00", c.digits)

    let e = computeState(d(2026, 11, 2, 20, 15), cfg())
    check("下班后", e.phase == .off && e.digits == "02:15:00" && e.progress == 1, e.digits)

    let withBreak = cfg { $0.breakEnabled = true }
    let f = computeState(d(2026, 11, 2, 15, 27, 30), withBreak)
    check("午休扣减进度", abs(f.progress - 0.6823) < 0.002, String(format: "%.4f", f.progress))
    let g = computeState(d(2026, 11, 2, 12, 30), withBreak)
    check("午休中状态", g.title.contains("午休") && g.quote.contains("午休"), g.title)

    let night = cfg { $0.start = "22:00"; $0.end = "06:00" }
    let h = computeState(d(2026, 11, 4, 2, 0), night) // 周三凌晨，属于周二的夜班
    check("跨零点班次进行中", h.phase == .working && h.digits == "04:00:00", h.digits)
    let i = computeState(d(2026, 11, 4, 7, 0), night)
    check("跨零点下班后", i.phase == .off && i.digits == "01:00:00", "\(i.phase) \(i.digits)")

    let holiday = cfg { $0.dayOverrides = ["2026-11-02": 0] }
    let j = computeState(d(2026, 11, 2, 15, 0), holiday)
    check("标记放假覆盖工作日", j.phase == .rest, j.title)
    let makeup = cfg { $0.dayOverrides = ["2026-11-01": 1] }
    let k = computeState(d(2026, 11, 1, 15, 0), makeup)
    check("标记补班覆盖休息日", k.phase == .working, k.title)

    let n = nextWorkStart(d(2026, 11, 7, 10, 0), cfg()) // 周六 → 周一
    check("跨周末下次上班", n.map { dayKey($0) == "2026-11-09" && hhmmString($0) == "09:00" } ?? false,
          n.map { dayKey($0) + " " + hhmmString($0) } ?? "nil")

    let none = cfg { $0.workdays = [] }
    let l = computeState(d(2026, 11, 2, 15, 0), none)
    check("无工作日", l.phase == .rest && l.label == "永远不用上班", l.label)

    // 跨周末：周五下班瞬间必须仍是「已下班」，不能误判成休息日
    let fri = computeState(d(2026, 11, 6, 18, 0), cfg())
    check("周五下班瞬间仍是已下班", fri.phase == .off && fri.digits == "00:00:00",
          "\(fri.phase) \(fri.title)")
    let sat = computeState(d(2026, 11, 7, 6, 1), cfg())
    check("周末凌晨切为倒数到周一", sat.phase == .rest && sat.digits == "50:59:00",
          "\(sat.phase) \(sat.digits)")

    check("精简菜单栏只到分钟", a.menuShort == "2:32" && a.menu == "🕕 02:32:30", a.menuShort)
    check("精简菜单栏下班", e.menuShort == "下班", e.menuShort)
    check("精简菜单栏休息日", b.menuShort == "休息" && shortMinutes("00:03:12") == "0:03", b.menuShort)
    let iconNames = ["clock.fill", "checkmark.circle.fill", "moon.fill"]
    check("三态图标映射",
          statusIconName(a.phase) == iconNames[0] &&
          statusIconName(e.phase) == iconNames[1] &&
          statusIconName(b.phase) == iconNames[2], "")
    check("状态图标可加载且互不相同",
          Set(iconNames).count == 3 &&
          iconNames.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }, "")
    let sizedCfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    let sized = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(sizedCfg)
    check("SF Symbol 尺寸配置生效", (sized?.size.width ?? 0) >= 19,
          "\(sized?.size.width ?? 0)pt")

    check("进度环 clamp 0...1",
          ringSegments(phase: .working, progress: 1.8, isStealth: false).progress == 1 &&
          ringSegments(phase: .working, progress: -0.3, isStealth: false).progress == 0, "")
    let rsW = ringSegments(phase: .working, progress: 0.4, isStealth: false)
    let rsO = ringSegments(phase: .off, progress: 0, isStealth: false)
    let rsR = ringSegments(phase: .rest, progress: 0, isStealth: false)
    check("进度环三态形态",
          rsW.filled && !rsW.dashed && !rsW.centerDot && rsW.progress == 0.4 &&
          rsO.centerDot && rsO.progress == 1 && rsR.dashed, "")
    let rsH = ringSegments(phase: .working, progress: 0.9, isStealth: true)
    check("进度环隐身降级", !rsH.filled && !rsH.dashed && rsH.baseAlpha < 0.15, "")

    let d0   = ringDotColor(phase: .working, progress: 0,    isStealth: false)
    let d25  = ringDotColor(phase: .working, progress: 0.25, isStealth: false)
    let d50  = ringDotColor(phase: .working, progress: 0.5,  isStealth: false)
    let d75  = ringDotColor(phase: .working, progress: 0.75, isStealth: false)
    let d100 = ringDotColor(phase: .working, progress: 1,    isStealth: false)
    check("色点 0–25% 绿", d0.map { $0.g > $0.r && $0.g > $0.b } ?? false, "")
    check("色点 25–50% 黄",
          d25.map { $0.r > $0.g && $0.g > (d50?.g ?? 1) } ?? false && d25 != d0, "")
    check("色点 50–75% 橙",
          d50 != nil && d50 != d25 && d50 != d0 &&
          ringDotColor(phase: .working, progress: 0.749, isStealth: false) == d50, "")
    check("色点 75–100% 红",
          (d100.map { $0.r > $0.g && $0.r > $0.b } ?? false) &&
          d75 == d100 && d75 != d50, "")
    check("色点四档边界",
          ringDotColor(phase: .working, progress: 0.249, isStealth: false) == d0 &&
          ringDotColor(phase: .working, progress: 0.25,  isStealth: false) == d25 &&
          ringDotColor(phase: .working, progress: 0.499, isStealth: false) == d25 &&
          ringDotColor(phase: .working, progress: 0.5,   isStealth: false) == d50 &&
          ringDotColor(phase: .working, progress: 0.749, isStealth: false) == d50 &&
          ringDotColor(phase: .working, progress: 0.75,  isStealth: false) == d75, "")
    check("色点 clamp 与状态隐藏",
          ringDotColor(phase: .working, progress: 2, isStealth: false) != nil &&
          ringDotColor(phase: .rest, progress: 0.5, isStealth: false) == nil &&
          ringDotColor(phase: .off, progress: 1, isStealth: false) == nil &&
          ringDotColor(phase: .working, progress: 0.5, isStealth: true) == nil, "")

    // 20x22 的菜单栏视图内，放大后的色点不越界且与环外缘(8pt)有重叠
    let geo = ringDotGeometry(ringCenter: CGPoint(x: 10, y: 11), ringRadius: 7)
    let gdx = geo.center.x - 10, gdy = geo.center.y - 11
    check("色点放大后不越界且压住环",
          geo.center.x - geo.radius >= 0 && geo.center.x + geo.radius <= 20 &&
          geo.center.y - geo.radius >= 0 && geo.center.y + geo.radius <= 22 &&
          sqrt(gdx * gdx + gdy * gdy) - geo.radius < 8,
          "r=\(geo.radius)")

    let oldJSON = "{\"start\":\"09:30\",\"end\":\"19:00\",\"compact\":true}".data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(Prefs.self, from: oldJSON)
    check("旧配置向后兼容", decoded?.start == "09:30" && decoded?.palette == 0
          && decoded?.dayOverrides.isEmpty == true && decoded?.stealth == false, "")

    if failures > 0 { print("SELFTEST FAILED: \(failures) case(s)"); exit(1) }
    print("SELFTEST PASSED (33 cases)")
}

// MARK: - 数据仓库

final class Store: ObservableObject {
    @Published var prefs: Prefs { didSet { save() } }
    @Published var now = Date()
    @Published var timeError: String?

    private static let key = "com.rumor.offwork-countdown.prefs.v1"

    init() {
        if let s = UserDefaults.standard.string(forKey: Store.key),
           let d = s.data(using: .utf8),
           let p = try? JSONDecoder().decode(Prefs.self, from: d) {
            prefs = p.validated()
        } else {
            prefs = Prefs()
        }
    }

    var state: CountdownState { computeState(now, prefs) }

    /// 隐身中：手动隐身或临时隐身未到期
    var isStealth: Bool {
        prefs.stealth || (prefs.stealthUntil ?? 0) > Date().timeIntervalSince1970
    }

    func toggleStealth() {
        if isStealth { reveal() }
        else { prefs.stealth = true; prefs.stealthUntil = nil }
    }

    func reveal() {
        prefs.stealth = false
        prefs.stealthUntil = nil
    }

    func stealthFor(minutes: Double) {
        prefs.stealth = false
        prefs.stealthUntil = Date().addingTimeInterval(minutes * 60).timeIntervalSince1970
    }

    func clearExpiredStealth() {
        if let until = prefs.stealthUntil, until <= Date().timeIntervalSince1970 {
            prefs.stealthUntil = nil
        }
    }

    func save() {
        guard let d = try? JSONEncoder().encode(prefs), let s = String(data: d, encoding: .utf8) else { return }
        UserDefaults.standard.set(s, forKey: Store.key)
    }

    // 下班时间早于上班时间 = 跨零点班次，合法
    func setStart(_ s: String) { prefs.start = s; timeError = nil }
    func setEnd(_ s: String) { prefs.end = s; timeError = nil }

    func toggleDay(_ d: Int) {
        if let i = prefs.workdays.firstIndex(of: d) { prefs.workdays.remove(at: i) }
        else { prefs.workdays.append(d) }
        prefs.workdays.sort()
    }

    func setLaunchAtLogin(_ on: Bool) {
        var ok = false
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                ok = true
            } catch { ok = false }
        }
        if !ok { ok = writeLaunchAgent(on) }
        if ok { prefs.launchAtLogin = on; timeError = nil }
        else { timeError = "设置失败，请到「系统设置 → 通用 → 登录项」手动添加" }
    }

    private func writeLaunchAgent(_ on: Bool) -> Bool {
        let fm = FileManager.default
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        let path = dir + "/com.rumor.offwork-countdown.plist"
        if on {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let dict: [String: Any] = [
                    "Label": "com.rumor.offwork-countdown",
                    "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                    "RunAtLoad": true
                ]
                return (dict as NSDictionary).write(toFile: path, atomically: true)
            } catch { return false }
        } else {
            try? fm.removeItem(atPath: path)
            return true
        }
    }
}

// MARK: - SwiftUI 视图

extension Notification.Name {
    static let owOpenSettings = Notification.Name("com.rumor.offwork-countdown.openSettings")
}

func preferredScheme(_ theme: Int) -> ColorScheme? {
    if theme == 1 { return .dark }
    if theme == 2 { return .light }
    return nil
}

// MARK: - 配色

struct RGB {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(max(r, 0), 1); self.g = min(max(g, 0), 1); self.b = min(max(b, 0), 1)
    }

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6, let v = UInt32(s, radix: 16) {
            self.init(Double((v >> 16) & 0xFF) / 255,
                      Double((v >> 8) & 0xFF) / 255,
                      Double(v & 0xFF) / 255)
        } else {
            self.init(0.486, 0.576, 0.659) // 默认雾蓝 #7C93A8
        }
    }

    init(_ color: Color) {
        if let cg = color.cgColor,
           let ns = NSColor(cgColor: cg)?.usingColorSpace(.deviceRGB) {
            self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        } else {
            self.init(hex: "#7C93A8")
        }
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    var hex: String {
        String(format: "#%02X%02X%02X", UInt32(r * 255), UInt32(g * 255), UInt32(b * 255))
    }

    func lighten(_ t: Double) -> RGB { RGB(r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t) }
    func darken(_ t: Double) -> RGB { RGB(r * (1 - t), g * (1 - t), b * (1 - t)) }
}

/// 低饱和配色（默认 0 雾蓝），每套三个色标用于渐变
let PALETTES: [(name: String, hexes: [String])] = [
    ("雾蓝", ["#6E8CA8", "#9DB3C6", "#7F94AE"]),
    ("石墨", ["#7B828C", "#A7AEB7", "#6E757F"]),
    ("鼠尾草", ["#7E9B8E", "#A9C0B3", "#8AA697"]),
    ("暖砂", ["#B49A91", "#CDB6AC", "#A78C86"]),
    ("霞光", ["#D9A07E", "#C9A4B0", "#9AA4C8"]),
]

func paletteColors(_ p: Prefs) -> [Color] {
    switch p.palette {
    case 0...4:
        return PALETTES[p.palette].hexes.map { RGB(hex: $0).color }
    case 5:
        let c = Color.accentColor
        return [c.opacity(0.68), c, c.opacity(0.60)]
    default:
        let base = RGB(hex: p.customHex)
        return [base.darken(0.14).color, base.color, base.lighten(0.20).color]
    }
}

func swatchColors(_ i: Int, customHex: String) -> [Color] {
    if i < PALETTES.count { return PALETTES[i].hexes.map { RGB(hex: $0).color } }
    if i == 5 { return [Color.accentColor.opacity(0.6), Color.accentColor] }
    let b = RGB(hex: customHex)
    return [b.darken(0.12).color, b.lighten(0.18).color]
}

struct DigitsText: View {
    let st: CountdownState
    let size: CGFloat
    let colors: [Color]
    var body: some View {
        Text(st.digits)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
    }
}

struct ProgressBar: View {
    let value: Double
    let colors: [Color]
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 7)
        .animation(.easeInOut(duration: 0.7), value: value)
    }
}

/// 悬浮窗内容：可收缩成一个不显示任何数字的小图标
struct PanelRoot: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let p = store.prefs
        let width: CGFloat? = p.collapsed ? nil : (p.compact ? 200 : 300)
        let corner: CGFloat = p.collapsed ? 12 : 18
        return Group {
            if p.collapsed {
                miniView
            } else {
                fullView(st: store.state, p: p, colors: paletteColors(p))
            }
        }
        .padding(.horizontal, p.collapsed ? 0 : 16)
        .padding(.vertical, p.collapsed ? 0 : 12)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.primary.opacity(0.13), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .opacity(p.panelOpacity)
        .preferredColorScheme(preferredScheme(p.theme))
        .contextMenu {
            Button(p.collapsed ? "展开悬浮窗" : "收缩悬浮窗") { store.prefs.collapsed.toggle() }
            Button(p.compact ? "切换到完整模式" : "切换到紧凑模式") { store.prefs.compact.toggle() }
            Divider()
            Button(store.isStealth ? "恢复显示" : "立即隐身（⌃⌥⌘H）") { store.toggleStealth() }
            Button("隐身 30 分钟") { store.stealthFor(minutes: 30) }
            Divider()
            Button("设置…") { NotificationCenter.default.post(name: .owOpenSettings, object: nil) }
            Button("退出") { NSApp.terminate(nil) }
        }
    }

    /// 收缩态：只有一个小图标，完全不显示倒计时
    private var miniView: some View {
        HStack(spacing: 3) {
            Text("🕕").font(.system(size: 12))
            Image(systemName: "plus").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(width: 46, height: 30)
        .contentShape(Rectangle())
        .onTapGesture { store.prefs.collapsed = false }
        .help("点击展开；右键可完全隐身")
    }

    private func fullView(st: CountdownState, p: Prefs, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(colors[0]).frame(width: 6, height: 6)
                Text(st.title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    store.prefs.collapsed = true
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.plain)
                .opacity(0.5)
                .help("收缩成一个小图标（不显示倒计时）")
            }
            .padding(.bottom, p.compact ? 5 : 8)

            DigitsText(st: st, size: p.compact ? 30 : 42, colors: colors)
                .padding(.bottom, p.compact ? 2 : 8)

            if !p.compact {
                ProgressBar(value: st.progress, colors: colors)
                HStack {
                    Text(st.label).font(.system(size: 9.5))
                    Spacer()
                    Text("\(Int(st.progress * 100))%").font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.top, 5)

                Text(st.sub).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).padding(.top, 4)
                Text(st.quote).font(.system(size: 10)).lineLimit(2).padding(.top, 5)
            }
        }
    }
}

/// 点击菜单栏弹出的主面板：详情 + 设置
struct MenuView: View {
    @EnvironmentObject var store: Store

    private let dayLabels = [1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 0: "日"]
    private let dayOrder = [1, 2, 3, 4, 5, 6, 0]
    @State private var pickedDate = Date()

    var body: some View {
        let st = store.state
        let colors = paletteColors(store.prefs)
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
            // 概览
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(st.title).font(.headline)
                    Spacer()
                    Text("\(Calendar.current.component(.month, from: store.now))/\(Calendar.current.component(.day, from: store.now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DigitsText(st: st, size: 38, colors: colors)
                Text(st.label).font(.caption).foregroundStyle(.secondary)
                ProgressBar(value: st.progress, colors: colors).padding(.top, 4)
                Text(st.sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }

            Divider()

            // 作息
            HStack {
                Text("上班").font(.caption).frame(width: 28, alignment: .leading)
                DatePicker("", selection: Binding<Date>(
                    get: { dateFromHHMM(store.prefs.start) },
                    set: { store.setStart(hhmmString($0)) }
                ), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 100)
                Spacer()
                Text("下班").font(.caption).frame(width: 28, alignment: .leading)
                DatePicker("", selection: Binding<Date>(
                    get: { dateFromHHMM(store.prefs.end) },
                    set: { store.setEnd(hhmmString($0)) }
                ), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 100)
            }

            HStack(spacing: 6) {
                Text("工作日").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                ForEach(dayOrder, id: \.self) { d in
                    Text(dayLabels[d] ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 23)
                        .background(store.prefs.workdays.contains(d) ? colors[1] : Color.primary.opacity(0.08))
                        .foregroundStyle(store.prefs.workdays.contains(d) ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { store.toggleDay(d) }
                }
            }

            if isCrossMidnight(store.prefs) {
                Text("跨零点班次：\(store.prefs.start) 上班 → 次日 \(store.prefs.end) 下班")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Toggle("午休不计入进度", isOn: $store.prefs.breakEnabled)
                .toggleStyle(.switch).controlSize(.small).font(.caption)
            if store.prefs.breakEnabled {
                HStack(spacing: 6) {
                    Text("午休").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                    DatePicker("", selection: Binding<Date>(
                        get: { dateFromHHMM(store.prefs.breakStart ?? "12:00") },
                        set: { store.prefs.breakStart = hhmmString($0) }
                    ), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 100)
                    Text("至").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding<Date>(
                        get: { dateFromHHMM(store.prefs.breakEnd ?? "13:00") },
                        set: { store.prefs.breakEnd = hhmmString($0) }
                    ), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 100)
                }
            }

            DisclosureGroup("节假日 / 调休（按日期覆盖）") {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $pickedDate, displayedComponents: .date)
                            .labelsHidden().frame(width: 112)
                        Button("设为补班") { store.prefs.dayOverrides[dayKey(pickedDate)] = 1 }
                        Button("设为放假") { store.prefs.dayOverrides[dayKey(pickedDate)] = 0 }
                    }
                    if store.prefs.dayOverrides.isEmpty {
                        Text("把调休补班日、法定假期逐日标记；覆盖优先级高于每周工作日。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(store.prefs.dayOverrides.keys.sorted(), id: \.self) { key in
                            HStack(spacing: 6) {
                                Text(key).font(.caption2).monospacedDigit()
                                Text(store.prefs.dayOverrides[key] == 1 ? "补班" : "放假")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("移除") { store.prefs.dayOverrides.removeValue(forKey: key) }
                                    .buttonStyle(.borderless).font(.caption2)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)

            if let err = store.timeError {
                Text(err).font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // 显示选项
            VStack(alignment: .leading, spacing: 7) {
                Toggle("显示悬浮窗", isOn: $store.prefs.showPanel)
                HStack {
                    Toggle("紧凑模式", isOn: $store.prefs.compact)
                    Spacer()
                    Toggle("总在最前", isOn: $store.prefs.alwaysOnTop)
                }
                HStack {
                    Toggle("下班提示音", isOn: $store.prefs.sound)
                    Spacer()
                    Toggle("登录时启动", isOn: Binding<Bool>(
                        get: { store.prefs.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                }
                HStack {
                    Text("外观").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $store.prefs.theme) {
                        Text("跟随系统").tag(0)
                        Text("深色").tag(1)
                        Text("浅色").tag(2)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 190)
                }
                HStack {
                    Text("菜单栏").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $store.prefs.menuStyle) {
                        Text("完整").tag(0)
                        Text("精简").tag(1)
                        Text("状态图标").tag(2)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 170)
                }
                HStack(spacing: 6) {
                    Text("配色").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: swatchColors(i, customHex: store.prefs.customHex),
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 30, height: 19)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(store.prefs.palette == i ? Color.primary : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture { store.prefs.palette = i }
                            .help(i < PALETTES.count ? PALETTES[i].name : (i == 5 ? "跟随系统强调色" : "自定义主色"))
                    }
                }
                if store.prefs.palette == 6 {
                    HStack(spacing: 8) {
                        Text("主色").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        ColorPicker("", selection: Binding<Color>(
                            get: { RGB(hex: store.prefs.customHex).color },
                            set: { store.prefs.customHex = RGB($0).hex }
                        ))
                        .labelsHidden().frame(width: 44)
                        Text(store.prefs.customHex.uppercased())
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    Text("透明度").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $store.prefs.panelOpacity, in: 0.4...1.0)
                    Text("\(Int(store.prefs.panelOpacity * 100))%").font(.caption2).monospacedDigit().frame(width: 34)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption)

            Divider()

            HStack(spacing: 8) {
                Button(store.prefs.collapsed ? "展开" : "收缩") { store.prefs.collapsed.toggle() }
                Button(store.isStealth ? "恢复显示" : "立即隐身") { store.toggleStealth() }
                Button("隐身 30 分") { store.stealthFor(minutes: 30) }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            Text("⌃⌥⌘H 一键隐身 / 恢复 · 隐身时点菜单栏时钟图标也能恢复\n悬浮窗可直接拖动；右键可打开菜单")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 298, alignment: .leading)
        }
        .frame(width: 330, height: 540)
        .preferredColorScheme(preferredScheme(store.prefs.theme))
    }
}

// MARK: - 悬浮窗

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panel: FloatingPanel!
    private var hostingView: NSHostingView<AnyView>!
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var lastPhase: Phase = .working
    private var contextMenu: NSMenu!
    private var stealthMenu: NSMenu!
    private var isShowingMenu = false
    private var trackingMoves = false
    private var currentIconName = ""
    private var ringView: RingStatusView?
    private var currentMenuStyle = -1
    private var ringUnavailable = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例：避免菜单栏出现多个图标
        let bundleID = Bundle.main.bundleIdentifier ?? "com.rumor.offwork-countdown"
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if !others.isEmpty {
            others.first?.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        // 手动隐身不跨重启保留，避免重启后只剩一个灰图标让人以为应用不见了
        // （「隐身 30 分钟」这类临时隐身仍按到期时间保留）
        if store.prefs.stealth { store.prefs.stealth = false }

        NSApp.setActivationPolicy(.accessory)
        buildContextMenu()
        setupStatusItem()
        setupPanel()
        setupPopover()

        cancellable = store.$prefs.sink { [weak self] prefs in
            self?.applyPrefs(prefs)
        }
        applyPrefs(store.prefs)

        lastPhase = store.state.phase
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        tick()

        let hotKeyStatus = registerGlobalHotKey { [weak self] in
            self?.store.toggleStealth()
        }
        if hotKeyStatus != noErr {
            NSLog("下班倒计时：全局热键注册失败（\(hotKeyStatus)），仍可用菜单 / 设置切换隐身")
        }

        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)),
                                               name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .owOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        // 等初始布局通知都走完，再开始记录用户拖动
        DispatchQueue.main.async { self.trackingMoves = true }
        // 启动后 SwiftUI 完成首次布局再精修一次窗口尺寸（幂等）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.resizePanelToFit() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.resizePanelToFit() }
    }

    private func setupStatusItem() {
        rebuildStatusItem(style: store.prefs.menuStyle)
    }

    /// `statusItem.view` 与 `statusItem.button` 互斥，切换档位时重建整个 item
    private func rebuildStatusItem(style: Int) {
        if style != 2 {
            rebuildAsButton(style: style)
            return
        }
        if let old = statusItem { NSStatusBar.system.removeStatusItem(old) }
        currentMenuStyle = style
        statusItem = NSStatusBar.system.statusItem(withLength: 20)
        let v = RingStatusView(frame: NSRect(x: 0, y: 0, width: 20, height: 22))
        v.actionTarget = self
        v.leftAction = #selector(ringLeftClicked)
        v.rightAction = #selector(ringRightClicked)
        v.toolTip = "下班倒计时（左键打开面板，右键菜单）"
        statusItem.view = v
        if statusItem.view == nil {
            // 较老 API 未渲染时降级到 SF Symbol 三态图标
            ringUnavailable = true
            rebuildAsButton(style: 1)
            return
        }
        ringView = v
    }

    private func rebuildAsButton(style: Int) {
        if let old = statusItem { NSStatusBar.system.removeStatusItem(old) }
        ringView = nil
        currentMenuStyle = style
        statusItem = NSStatusBar.system.statusItem(withLength: style == 1 ? 42 : NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.title = ""
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPanel() {
        panel = FloatingPanel()
        hostingView = NSHostingView(rootView: AnyView(PanelRoot().environmentObject(store)))
        panel.contentView = hostingView
        // 首次布局前 fittingSize 可能不准，先按状态给一个接近的尺寸，稍后再精确重算
        let initial: NSSize = store.prefs.collapsed
            ? NSSize(width: 46, height: 30)
            : NSSize(width: store.prefs.compact ? 200 : 300, height: store.prefs.compact ? 92 : 165)
        panel.setContentSize(initial)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let o = store.prefs.panelOrigin, o.count == 2 {
            panel.setFrameOrigin(NSPoint(x: o[0], y: o[1]))
        } else {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 24,
                                         y: screen.maxY - panel.frame.height - 24))
        }
        ensurePanelOnScreen()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(rootView: AnyView(MenuView().environmentObject(store)))
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 330, height: 540)
    }

    private func applyPrefs(_ p: Prefs) {
        guard let panel = panel else { return }
        panel.level = p.alwaysOnTop ? .floating : .normal
        panel.setIsVisible(p.showPanel && !store.isStealth)
        if store.isStealth && popover.isShown { popover.performClose(nil) }
        if p.showPanel && !store.isStealth { ensurePanelOnScreen() }

        // SwiftUI 重绘发生在下一个 runloop，等它更新完再按内容尺寸调整窗口
        DispatchQueue.main.async { [weak self] in self?.resizePanelToFit() }
        refreshMenuStates()
        updateStatusItem(stealth: store.isStealth, st: store.state)
    }

    /// 按 SwiftUI 内容的实际尺寸调整窗口，保持顶部位置不动
    private func resizePanelToFit() {
        guard let panel = panel, let hv = hostingView else { return }
        let size = hv.fittingSize
        guard size.width > 0, size.height > 0,
              abs(panel.frame.width - size.width) > 1 || abs(panel.frame.height - size.height) > 1 else { return }
        var f = panel.frame
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        let wasTracking = trackingMoves
        trackingMoves = false
        panel.setFrame(f, display: true, animate: false)
        trackingMoves = wasTracking
    }

    /// 窗口若落在所有屏幕之外（例如拔掉外接显示器），移回主屏右上角
    private func ensurePanelOnScreen() {
        guard let panel = panel else { return }
        let f = panel.frame
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f) }) else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let wasTracking = trackingMoves
        trackingMoves = false
        panel.setFrameOrigin(NSPoint(x: screen.maxX - f.width - 24,
                                     y: screen.maxY - f.height - 24))
        trackingMoves = wasTracking
        store.prefs.panelOrigin = [Double(panel.frame.origin.x), Double(panel.frame.origin.y)]
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        ensurePanelOnScreen()
    }

    private func tick() {
        store.now = Date()
        store.clearExpiredStealth()
        let st = store.state
        updateStatusItem(stealth: store.isStealth, st: st)
        if st.phase != lastPhase {
            if st.phase == .off && store.prefs.sound && !store.isStealth { NSSound(named: "Glass")?.play() }
            lastPhase = st.phase
        }
    }

    /// 按 menuStyle 渲染菜单栏：2 = 自绘进度环；0/1 = 文字；隐身时隐藏文字
    private func updateStatusItem(stealth: Bool, st: CountdownState) {
        let style = store.prefs.menuStyle
        let effective = (style == 2 && ringUnavailable) ? 1 : style
        if effective != currentMenuStyle || statusItem == nil {
            rebuildStatusItem(style: effective)
        }

        // 进度环：仅值变化时重绘，避免 0.5s 空转
        if let v = ringView {
            let p = st.progress
            let brk = st.title.contains("午休")
            if v.phase != st.phase || abs(v.progress - p) > 0.0001 ||
                v.isStealth != stealth || v.isBreak != brk {
                v.phase = st.phase
                v.progress = p
                v.isStealth = stealth
                v.isBreak = brk
                v.needsDisplay = true
            }
            v.toolTip = stealth ? "下班倒计时（已隐身，点击恢复）"
                                : st.title + " · 点击查看详情"
            statusItem?.length = 20
            return
        }

        // 文字档；隐身时强制只留 SF Symbol 图标，不显示任何文字
        guard let button = statusItem?.button else { return }
        let iconOnly = stealth
        if iconOnly {
            let name = statusIconName(st.phase)
            if currentIconName != name {
                // SF Symbol 必须用 SymbolConfiguration 才能改变尺寸
                let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
                let img = NSImage(systemSymbolName: name, accessibilityDescription: st.title)?
                    .withSymbolConfiguration(cfg)
                img?.isTemplate = true
                button.image = img
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                currentIconName = name
            }
            button.title = ""
            button.toolTip = "下班倒计时（已隐身，点击恢复）"
        } else {
            if button.image != nil { button.image = nil }
            currentIconName = ""
            let text = effective == 0 ? st.menu : st.menuShort
            if button.title != text { button.title = text }
            button.toolTip = st.title + "（左键打开面板，右键菜单）"
        }
        statusItem?.length = iconOnly ? 26 : (effective == 1 ? 42 : NSStatusItem.variableLength)
    }

    @objc private func windowDidMove(_ note: Notification) {
        guard trackingMoves, let w = note.object as? NSWindow, w === panel else { return }
        store.prefs.panelOrigin = [Double(w.frame.origin.x), Double(w.frame.origin.y)]
    }

    // MARK: 菜单与交互

    private func buildContextMenu() {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector, _ tag: Int, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.tag = tag
            m.addItem(item)
        }
        add("收缩 / 展开悬浮窗", #selector(toggleCollapse), 1)
        add("立即隐身（⌃⌥⌘H）", #selector(toggleStealth), 2)
        add("隐身 30 分钟", #selector(stealth30), 5)
        m.addItem(.separator())
        add("显示 / 隐藏悬浮窗", #selector(togglePanel), 3)
        add("紧凑模式", #selector(toggleCompact), 4)
        m.addItem(.separator())
        add("设置…", #selector(openSettings), 0, ",")
        m.addItem(.separator())
        add("退出下班倒计时", #selector(quit), 0, "q")
        contextMenu = m

        // 隐身时右键只留「恢复显示」，避免弹出写着应用名的完整菜单
        let sm = NSMenu()
        let restore = NSMenuItem(title: "恢复显示（⌃⌥⌘H）", action: #selector(revealFromMenu), keyEquivalent: "")
        restore.target = self
        sm.addItem(restore)
        stealthMenu = sm
    }

    private func refreshMenuStates() {
        guard let m = contextMenu else { return }
        for item in m.items {
            switch item.tag {
            case 1: item.state = store.prefs.collapsed ? .on : .off
            case 2:
                item.title = store.isStealth ? "恢复显示（⌃⌥⌘H）" : "立即隐身（⌃⌥⌘H）"
                item.state = store.isStealth ? .on : .off
            case 3: item.state = store.prefs.showPanel ? .on : .off
            case 4: item.state = store.prefs.compact ? .on : .off
            case 5: item.state = (store.prefs.stealthUntil ?? 0) > Date().timeIntervalSince1970 ? .on : .off
            default: break
            }
        }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        // performClick 期间可能再次触发 action，用标志位防止递归
        guard !isShowingMenu else { return }
        let isRight = NSApp.currentEvent?.type == .rightMouseUp ||
                      (NSApp.currentEvent?.modifierFlags.contains(.control) ?? false)
        if isRight {
            isShowingMenu = true
            statusItem.menu = store.isStealth ? stealthMenu : contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            isShowingMenu = false
        } else {
            // 隐身时左键直接恢复，不弹出会暴露倒计时的面板
            if store.isStealth { store.reveal() }
            else { togglePopover() }
        }
    }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        // 自绘 view 模式下 statusItem.button 可能为 nil，直接用 ringView 定位
        if let v = ringView {
            popover.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func ringLeftClicked() {
        if store.isStealth { store.reveal() }
        else { togglePopover() }
    }

    @objc private func ringRightClicked() {
        let menu = store.isStealth ? stealthMenu : contextMenu
        guard let m = menu, let v = ringView else { return }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: v)
    }

    @objc private func toggleCollapse() { store.prefs.collapsed.toggle() }
    @objc private func toggleStealth() { store.toggleStealth() }
    @objc private func revealFromMenu() { store.reveal() }
    @objc private func stealth30() { store.stealthFor(minutes: 30) }
    @objc private func togglePanel() { store.prefs.showPanel.toggle() }
    @objc private func toggleCompact() { store.prefs.compact.toggle() }
    @objc private func openSettings() { togglePopover() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - 启动

if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
