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

    private enum CodingKeys: String, CodingKey {
        case start, end, workdays, showPanel, compact, alwaysOnTop, sound, theme,
             launchAtLogin, panelOpacity, panelOrigin, palette, customHex,
             collapsed, stealth, stealthUntil
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
    }

    func validated() -> Prefs {
        var p = self
        func mins(_ s: String) -> Int { let t = hhmm(s); return t.0 * 60 + t.1 }
        if mins(p.end) <= mins(p.start) { p.start = "09:00"; p.end = "18:00" }
        p.workdays = Array(Set(p.workdays.filter { $0 >= 0 && $0 <= 6 })).sorted()
        p.panelOpacity = min(max(p.panelOpacity, 0.4), 1.0)
        if p.theme < 0 || p.theme > 2 { p.theme = 0 }
        if p.palette < 0 || p.palette > 6 { p.palette = 0 }
        p.customHex = RGB(hex: p.customHex).hex
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
    var menu: String
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

func nextWorkStart(_ now: Date, _ p: Prefs) -> Date? {
    guard !p.workdays.isEmpty else { return nil }
    let cal = Calendar.current
    for i in 0...7 {
        guard let day = cal.date(byAdding: .day, value: i, to: now) else { continue }
        let wd = cal.component(.weekday, from: day) - 1
        guard p.workdays.contains(wd) else { continue }
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
        if p.workdays.contains(cal.component(.weekday, from: d) - 1) { n += 1 }
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
    let wd = cal.component(.weekday, from: now) - 1
    let isWorkday = p.workdays.contains(wd)
    let start = dateAt(p.start, on: now)
    let end = dateAt(p.end, on: now)
    let weekdayCN = ["日", "一", "二", "三", "四", "五", "六"]

    if !isWorkday {
        let nxt = nextWorkStart(now, p)
        let d = nxt.map { digits($0.timeIntervalSince(now)) } ?? "--:--:--"
        let sub: String
        if let n = nxt {
            let c = cal.dateComponents([.month, .day, .weekday], from: n)
            sub = "下次上班：\(c.month ?? 1) 月 \(c.day ?? 1) 日（周\(weekdayCN[(c.weekday ?? 1) - 1])）\(p.start)"
        } else {
            sub = "你把所有工作日都取消了，恭喜 🎊"
        }
        return CountdownState(phase: .rest, title: "今天不用上班 🎉", label: nxt == nil ? "永远不用上班" : "距离下次上班还有",
                              digits: d, progress: 0, sub: sub, quote: pick(QUOTES["rest"]!, now), menu: "🎉 休息日")
    }

    if now < start {
        return CountdownState(
            phase: .before, title: "还没上班，先别急 ☕", label: "距离上班还有",
            digits: digits(start.timeIntervalSince(now)), progress: 0,
            sub: "今天 \(p.start) 上班 · \(p.end) 下班 · 本周共 \(workdaysThisWeek(now, p)) 个工作日",
            quote: pick(QUOTES["before"]!, now),
            menu: "☕ \(hhmmString(start)) 上班")
    }

    if now < end {
        let remain = end.timeIntervalSince(now)
        return CountdownState(
            phase: .working, title: "摸鱼进行中 🐟", label: "距离下班还有",
            digits: digits(remain), progress: (now.timeIntervalSince(start)) / end.timeIntervalSince(start),
            sub: "已工作 \(human(now.timeIntervalSince(start))) · 今日共 \(human(end.timeIntervalSince(start)))",
            quote: workingQuote(remain, now),
            menu: "🕕 \(digits(remain))")
    }

    let off = now.timeIntervalSince(end)
    let nxt = nextWorkStart(now, p)
    let sub = "今日任务已结束 · " + (nxt.map { "距下次上班 \(human($0.timeIntervalSince(now)))" } ?? "没有排班") + " · 快回家吧"
    return CountdownState(
        phase: .off, title: "下班啦！🎉", label: "已经下班",
        digits: digits(off), progress: 1, sub: sub,
        quote: off > 4 * 3600 ? QUOTES["late"]![0] : pick(QUOTES["off"]!, now),
        menu: "✅ 下班啦")
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

    func setStart(_ s: String) {
        let a = hhmm(s), b = hhmm(prefs.end)
        guard a.0 * 60 + a.1 < b.0 * 60 + b.1 else {
            timeError = "下班时间需晚于上班时间（暂不支持跨零点排班）"; return
        }
        prefs.start = s; timeError = nil
    }

    func setEnd(_ s: String) {
        let a = hhmm(prefs.start), b = hhmm(s)
        guard a.0 * 60 + a.1 < b.0 * 60 + b.1 else {
            timeError = "下班时间需晚于上班时间（暂不支持跨零点排班）"; return
        }
        prefs.end = s; timeError = nil
    }

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

    var body: some View {
        let st = store.state
        let colors = paletteColors(store.prefs)
        return VStack(alignment: .leading, spacing: 12) {
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
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 330)
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
    private var isShowingMenu = false
    private var trackingMoves = false

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
        // 等初始布局通知都走完，再开始记录用户拖动
        DispatchQueue.main.async { self.trackingMoves = true }
        // 启动后 SwiftUI 完成首次布局再精修一次窗口尺寸（幂等）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.resizePanelToFit() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.resizePanelToFit() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.title = "🕕 …"
        button.toolTip = "下班倒计时（左键打开面板，右键菜单）"
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
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(rootView: AnyView(MenuView().environmentObject(store)))
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 330, height: 580)
    }

    private func applyPrefs(_ p: Prefs) {
        guard let panel = panel else { return }
        panel.level = p.alwaysOnTop ? .floating : .normal
        panel.setIsVisible(p.showPanel && !store.isStealth)
        if store.isStealth && popover.isShown { popover.performClose(nil) }

        // SwiftUI 重绘发生在下一个 runloop，等它更新完再按内容尺寸调整窗口
        DispatchQueue.main.async { [weak self] in self?.resizePanelToFit() }
        refreshMenuStates()
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

    private func tick() {
        store.now = Date()
        store.clearExpiredStealth()
        let st = store.state
        updateStatusItem(stealth: store.isStealth, title: st.menu)
        if st.phase != lastPhase {
            if st.phase == .off && store.prefs.sound && !store.isStealth { NSSound(named: "Glass")?.play() }
            lastPhase = st.phase
        }
    }

    /// 隐身时菜单栏只留一个灰色时钟图标，不显示任何倒计时文字
    private func updateStatusItem(stealth: Bool, title: String) {
        guard let button = statusItem?.button else { return }
        if stealth {
            if button.image == nil {
                let img = NSImage(systemSymbolName: "clock", accessibilityDescription: "下班倒计时（已隐身）")
                img?.isTemplate = true
                button.image = img
                button.imagePosition = .imageOnly
            }
            button.title = ""
            button.toolTip = "下班倒计时（已隐身，点击恢复）"
        } else {
            if button.image != nil { button.image = nil }
            button.title = title
            button.toolTip = "下班倒计时（左键打开面板，右键菜单）"
        }
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
            statusItem.menu = contextMenu
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
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func toggleCollapse() { store.prefs.collapsed.toggle() }
    @objc private func toggleStealth() { store.toggleStealth() }
    @objc private func stealth30() { store.stealthFor(minutes: 30) }
    @objc private func togglePanel() { store.prefs.showPanel.toggle() }
    @objc private func toggleCompact() { store.prefs.compact.toggle() }
    @objc private func openSettings() { togglePopover() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
