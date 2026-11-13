// 时间小工具、状态模型、语录池与班次 / 进度纯计算

import Foundation

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

// MARK: - 状态模型与语录池

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

// MARK: - 班次、状态计算与文案

func dayKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
}

/// 覆盖表优先：1 = 补班 / 0 = 放假；否则按每周工作日
func isWorkday(_ day: Date, _ p: Prefs) -> Bool {
    if let override = p.dayOverrides[dayKey(day)] { return override == 1 }
    return p.workdays.contains(Calendar.current.component(.weekday, from: day) - 1)
}

/// 解析某天生效的作息：当天日期覆盖 > 星期规则 > 全局默认
func schedule(for day: Date, _ p: Prefs) -> DaySchedule {
    if let d = p.dateOverrides[dayKey(day)] { return d }
    let w = Calendar.current.component(.weekday, from: day) - 1
    if let r = p.weekdayRules[String(w)] { return r }
    return DaySchedule(p.start, p.end)
}

/// 某天作息是否跨零点（end <= start）
func scheduleCrossesMidnight(for day: Date, _ p: Prefs) -> Bool {
    let s = schedule(for: day, p)
    let a = hhmm(s.start), b = hhmm(s.end)
    return a.0 * 60 + a.1 >= b.0 * 60 + b.1
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

/// 单日班次（含净工时与午休），非工作日返回 nil
func dayShift(_ day: Date, _ p: Prefs) -> Shift? {
    guard isWorkday(day, p) else { return nil }
    let cal = Calendar.current
    let sched = schedule(for: day, p)
    let s = dateAt(sched.start, on: day)
    var e = dateAt(sched.end, on: day)
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
    return Shift(day: day, start: s, end: e, breakStart: bs, breakEnd: be)
}

/// now 前后各两天的工作日班次；end <= start 时视为次日下班（跨零点）
func shifts(around now: Date, _ p: Prefs) -> [Shift] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    var result: [Shift] = []
    for offset in -2...2 {
        guard let day = cal.date(byAdding: .day, value: offset, to: today),
              let sh = dayShift(day, p) else { continue }
        result.append(sh)
    }
    return result.sorted { $0.start < $1.start }
}

// MARK: - 周进度

/// 本周一 00:00（以周一为一周起点）
func weekStart(_ now: Date) -> Date {
    let cal = Calendar.current
    let wd = cal.component(.weekday, from: now)   // 1=周日 ... 7=周六
    let offset = (wd + 5) % 7                      // 距周一
    return cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: now)!)
}

/// 每周总工时（秒）：手动目标优先，否则按本周 7 天的作息规则自动求和
func weekTargetSeconds(_ now: Date, _ p: Prefs) -> Double {
    if let h = p.weeklyTargetHours, h > 0 { return h * 3600 }
    let cal = Calendar.current
    let monday = weekStart(now)
    var total = 0.0
    for i in 0..<7 {
        guard let day = cal.date(byAdding: .day, value: i, to: monday),
              let sh = dayShift(day, p) else { continue }
        total += sh.totalWork
    }
    return total
}

/// 本周一 00:00 至今的累计净工时（秒）
func weekWorkedSeconds(_ now: Date, _ p: Prefs) -> Double {
    let cal = Calendar.current
    let monday = weekStart(now)
    var sum = 0.0
    for i in 0..<7 {
        guard let day = cal.date(byAdding: .day, value: i, to: monday) else { continue }
        if cal.startOfDay(for: day) > now { break }
        guard let sh = dayShift(day, p), sh.start < now else { continue }
        let until = min(now, sh.end)
        let elapsed = until.timeIntervalSince(sh.start) - sh.breakElapsed(at: until)
        sum += max(0, elapsed)
    }
    return sum
}

/// 周进度 0...1；目标为 0 时返回 0
func weekProgress(_ now: Date, _ p: Prefs) -> Double {
    let target = weekTargetSeconds(now, p)
    guard target > 0 else { return 0 }
    return min(max(weekWorkedSeconds(now, p) / target, 0), 1)
}

/// 显示口径：0 当日 / 1 本周
func displayProgress(_ now: Date, _ p: Prefs, _ state: CountdownState) -> Double {
    p.progressMode == 1 ? weekProgress(now, p) : state.progress
}

func nextWorkStart(_ now: Date, _ p: Prefs) -> Date? {
    let cal = Calendar.current
    for i in 0...14 {
        guard let day = cal.date(byAdding: .day, value: i, to: now),
              isWorkday(day, p) else { continue }
        let s = dateAt(schedule(for: day, p).start, on: day)
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

