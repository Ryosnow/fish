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

let QUOTES: [String: [String]] = [
    "rest": [
        "今天不用上班，睡到自然醒才是正经事 🛌",
        "休息日请勿打开工作群，违者罚款一顿火锅 🍲",
        "把「下班」两个字从字典里删掉，今天全天都是你的 🌈",
        "出门走走吧，太阳不会等你开完会 ☀️",
        "周末的会议邀请，已自动归类为「未读」📭",
        "被窝是今天的办公室，Wi-Fi 信号良好 📶",
        "阳光、咖啡、没有待办，三件套齐了 ☕",
        "今天的成功率 100%：因为没安排任何事 ✅",
        "闹钟关掉，日程表上只有「休息」一项 🔕",
        "今天的待办是「没有待办」📭",
        "连天气都在放假 ☀️",
        "手机静音，世界安静 🔕",
    ],
    "before": [
        "还没到上班时间，慢慢喝完这杯咖啡 ☕",
        "通勤路上的每一分钟，都算在人生里 🚇",
        "早到不如巧到，先看看今天天气 ☁️",
        "打卡前的最后几分钟，属于你自己 ⏳",
        "先把手放上键盘，脑子可以晚点到 🧠",
        "今日份的咖啡，正在加载中 🥤",
        "早会还有一会儿，先把窗户打开 🪟",
        "工牌还没戴正，不急 🪪",
        "离打卡还有一首歌的时间 🎧",
        "电梯里先深呼吸一次 🛗",
        "早晨的工位，还没被消息占领 🌅",
        "先把水接好，再开工 🥤",
    ],
    "far": [
        "路还很长，先给自己泡杯茶 🍵",
        "别急，上午会过完的，下午也会过完的 ⏳",
        "把最难的需求留到「明天再说」，是古老的智慧 📜",
        "今天的 KPI 是：平安活到下班 🐟",
        "上午很长，先挑一件最轻松的事做 🌤️",
        "距离下班还有一整个下午，先别慌 🧘",
        "把会议排到下午，是成年人的战术 📅",
        "进度条会自己走，你只要别关机 🖥️",
        "先回一封邮件，剩下的交给时间 ✉️",
        "今天也是稳稳当当的一天 🍃",
        "待办清单很长，但咖啡还很满 ☕",
        "先做最像工作的那件事，剩下的自然像摸鱼 🐟",
        "需求文档可以先最小化，心情不能 📄",
        "屏幕亮了，脑子还在启动中 💻",
        "别人在开会，你在赶进度，扯平了 ⚖️",
        "今日不宜重构，宜按部就班 📐",
        "给下午留点简单的活儿，是远见 🔭",
        "上午的时间最经得起浪费一点点 ⏳",
        "茶还热，事情不急，顺序排好就行 🍵",
        "进度条还空着，别慌，它刚起跑 🏁",
        "今天最难的一件事，先跟它打个招呼 👋",
        "把大任务拆成小任务，是今天唯一的魔法 ✨",
        "第一个会议还没开始，珍惜这段安静 🤫",
        "上午适合处理难事，也适合先缓缓 🌿",
        "先回最上面那封邮件，仪式感有了 ✉️",
        "稳住，上午的太阳还没到头顶 ☀️",
    ],
    "mid": [
        "过半了！下午的太阳比较温柔 🌤️",
        "伸个懒腰，颈椎比你更想下班 🦴",
        "此刻适合站起来接杯水，顺便巡逻一下茶水间 🚶",
        "再撑一会儿，胜利在望 💪",
        "过半了，奖励自己一块小饼干 🍪",
        "下午三点，血糖和士气一起回升 🍬",
        "这段最适合处理不费脑的活儿 📋",
        "窗外光线正好，适合发会儿呆 🪟",
        "再开一个会，今天就算圆满了 🎯",
        "过半了，把椅子往后仰三秒 🪑",
        "下午的第一杯水，比上午的更解渴 🥤",
        "会议纪要写完，今天就有了形状 📝",
        "困意来了，站起来走一圈比咖啡管用 🚶",
        "过半的进度条，看着比上午顺眼 📊",
        "这段最适合清收件箱，成就感稳定 📥",
        "把复杂的留到明天，是下午的智慧 📜",
        "窗外的光斜了，离下班又近一格 🌇",
        "下午三点的风，替你翻了一页 ☁️",
        "再回两封邮件，就可以合理发呆 ✉️",
        "过半了，别开新的坑，先填旧的 🕳️",
        "小饼干和进度条，都在稳步推进 🍪",
        "这段不争不抢，稳稳地过就好 🧘",
        "今天的士气，靠一杯奶茶续费 🧋",
        "屏幕反光里，看见快下班的自己 🖥️",
    ],
    "hour": [
        "最后一小时，别开新需求了 ⚠️",
        "收尾时间：提交、保存、写日报 📝",
        "开始整理桌面，物理和心理上的都要 🧹",
        "最后一小时，文档比雄心重要 📄",
        "把明天的待办写下来，然后关掉 📝",
        "别在此时重构，真的 🚫",
        "收尾清单：提交、同步、说声辛苦了 ✅",
        "窗口关到只剩一个，就很接近了 🖥️",
        "最后一小时，别答应任何新事 🙅",
        "把明天的第一行代码留到明天 💻",
        "提交信息写清楚，是给明天的自己留灯 💡",
        "收尾阶段，静音比专注有用 🔕",
        "最后一个会结束，胜利在望 🎯",
        "关掉一半标签页，心里就轻了 🖥️",
        "日报写三行，诚实又体面 📝",
        "别在此时优化，真的 🛑",
        "这一小时属于收尾，不属于雄心 🧹",
        "把文件存好，剩下的交给明天 📂",
        "最后一小时，适合说「这个明天跟」🗓️",
        "键盘声慢下来，节奏就对了 ⌨️",
        "先同步，再关电脑，顺序别乱 🔄",
        "今天交付得够多了，收工前的安静很值钱 🌙",
    ],
    "minutes": [
        "十分钟倒计时，关掉多余的标签页 🖥️",
        "把包放在最顺手的位置 🎒",
        "电梯在等你，别让电梯等太久 🛗",
        "把水杯洗干净，仪式感拉满 🥤",
        "工牌翻到背面，进入待机状态 🪪",
        "消息设个免打扰，明天见 🔕",
        "椅子推回去，这一步很关键 🪑",
        "外套先搭椅背上，随时能走 🧥",
        "把桌面图标摆正，算是收工仪式 🗂️",
        "水杯空了，正好去接最后一杯 🥤",
        "消息回完这一条，就切免打扰 🔕",
        "耳机摘下来，世界先安静一半 🎧",
        "把椅子归位，给明天留个好开始 🪑",
        "工牌翻过来，进入待机 🪪",
        "最后几个通知，看完就关 📱",
        "包拉链拉上，声音很治愈 🎒",
        "屏幕亮度调低，像在预告收工 🌙",
        "这段倒计时，比上午的会议温柔 ⏳",
        "外套搭胳膊上，随时能走 🧥",
        "电梯快到了，别再点刷新 🛗",
    ],
    "final": [
        "站起来！拿包！走人！🚪",
        "最后 60 秒，祝一路绿灯 🚦",
        "保存，提交，关机，一气呵成 💾",
        "倒数开始，别点「新建」🚫",
        "外套、钥匙、耳机，三件套 🧥",
        "今天的你，已经交付得够多了 🙌",
        "电梯到了，故事明天续 🛗",
        "屏幕暗下去的那一刻，最治愈 🌙",
        "倒数了，别点「同步全部」🚫",
        "保存！先保存！💾",
        "最后十行代码，明天再看也认得 💻",
        "关灯、锁屏、走人，三连 🌙",
        "今天的最后一条消息，是「明天见」👋",
        "站起来那一秒，进度条也松了口气 🧘",
        "钥匙在口袋，心已经到楼下 🔑",
        "别回头看屏幕，它明天还在 🖥️",
        "收工快乐，今天没白过 🙌",
        "电梯门一开，工作日就翻篇了 🛗",
    ],
    "off": [
        "今天辛苦了，快溜！🏃",
        "下班不积极，思想有问题 😌",
        "工作消息已进入「明天再说」模式 📴",
        "今晚属于你自己，去吃点好的 🍜",
        "已下班，消息已读不回是合理设置 🔕",
        "今晚的月亮不查考勤 🌙",
        "把「工作」文件夹合上，去生活 📂",
        "辛苦了，路上一路绿灯 🚦",
        "今天的待办，已经全部交给明天 📅",
        "今天到此为止，剩下的明天接 📅",
        "走出楼门那一步，最轻松 🚪",
        "今晚不谈需求，只谈吃什么 🍜",
    ],
    "late": [
        "都这个点了，该睡了 😴 明天还要上班呢",
        "夜深了，手机也该下班了 📱",
        "熬夜不还给你时间，只还给你黑眼圈 🌙",
        "明天的自己会感谢现在关灯的你 💤",
        "再刷一条就睡，这句话今晚第几次了 📵",
        "再不睡，明早的闹钟要赢 ⏰",
        "夜很深了，明天不急这一时 🌙",
        "关灯吧，屏幕不会想你 💤",
    ],
    "break": [
        "休息中，进度条也喘口气 🍚",
        "这一段不算工时，但算生活 🍵",
        "吃完再战，需求不会跑 🍜",
        "离开屏幕两分钟，眼睛谢谢你 👀",
        "休息是配置，不是摸鱼 ⚙️",
        "慢慢吃，时间这一刻归你 ⏳",
        "这一段是给身体发的工资 🍚",
        "慢一点吃，进度条不抢这一口 🥢",
        "离开键盘两分钟，回来手更稳 ⌨️",
        "休息不是暂停，是续航 🔋",
    ],
    "night": [
        "这么晚了还在，记得给自己留盏灯 💡",
        "深夜的需求，明天看会变简单 🌙",
        "夜班辛苦了，热水比咖啡温柔 ☕",
        "屏幕亮度调低一点，对眼睛好 🖥️",
        "这个点的提交，明天再 review 也不迟 📝",
        "城市睡了，你这条提交还亮着 🌃",
        "夜里的 bug，白天看会小一点 🐛",
        "这个点还亮着的屏幕，值得一杯热水 ☕",
        "深夜的提交备注，明早读起来像诗 📝",
        "城市都静了，你还在收尾，辛苦 🌃",
        "别跟夜较劲，先保存再说 💾",
        "凌晨的思路，天亮再验证一次 🌅",
        "夜班的人，和白班的月亮是同一个 🌙",
        "把亮度调低，别让眼睛陪你熬夜 🖥️",
        "深夜的会议纪要，明天读会短一点 📝",
        "楼道灯还亮着，别急，慢慢收 🌙",
        "夜越深，越不值得跟一行代码较劲 💻",
        "先把电脑合上，天亮再说 🌅",
    ],
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

/// 一段已对齐到班次内的休息（带名称，供状态文案使用）
struct BreakInterval {
    var start: Date
    var end: Date
    var name: String
}

struct Shift {
    var day: Date
    var start: Date
    var end: Date
    var breaks: [BreakInterval]

    var breakLength: TimeInterval {
        breaks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
    var totalWork: TimeInterval { max(0, end.timeIntervalSince(start) - breakLength) }
    func breakElapsed(at now: Date) -> TimeInterval {
        breaks.reduce(0.0) { sum, b in
            if now <= b.start { return sum }
            return sum + min(now, b.end).timeIntervalSince(b.start)
        }
    }
    func currentBreak(at now: Date) -> BreakInterval? {
        breaks.first { now >= $0.start && now < $0.end }
    }
    func inBreak(_ now: Date) -> Bool { currentBreak(at: now) != nil }
}

/// 单日班次（含净工时与午休），非工作日返回 nil
func dayShift(_ day: Date, _ p: Prefs) -> Shift? {
    guard isWorkday(day, p) else { return nil }
    let cal = Calendar.current
    let sched = schedule(for: day, p)
    let s = dateAt(sched.start, on: day)
    var e = dateAt(sched.end, on: day)
    if e <= s { e = cal.date(byAdding: .day, value: 1, to: e) ?? e }

    // 通用多段休息：每段对齐到班次、裁剪到 [start, end]、再合并重叠，避免重复扣工时
    var intervals: [BreakInterval] = []
    if !p.breakPeriods.isEmpty {
        func align(_ t: Date, after anchor: Date) -> Date {
            var t = t
            while t < anchor { t = cal.date(byAdding: .day, value: 1, to: t) ?? t }
            return t
        }
        for bp in p.breakPeriods where bp.enabled {
            let b1 = align(dateAt(bp.start, on: day), after: s)
            var b2 = align(dateAt(bp.end, on: day), after: b1)
            if b2 <= b1 { b2 = cal.date(byAdding: .day, value: 1, to: b2) ?? b2 }
            let cs = max(b1, s), ce = min(b2, e)
            if ce > cs { intervals.append(BreakInterval(start: cs, end: ce, name: bp.name)) }
        }
        intervals.sort { $0.start < $1.start }
        var merged: [BreakInterval] = []
        for iv in intervals {
            if var last = merged.last, iv.start <= last.end {
                last.end = max(last.end, iv.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(iv)
            }
        }
        intervals = merged
    }
    return Shift(day: day, start: s, end: e, breaks: intervals)
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
    let hour = Calendar.current.component(.hour, from: now)
    if hour >= 21 || hour < 6 { return pick(QUOTES["night"]!, now) }   // 深夜仍在上班
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
        let activeBreak = sh.currentBreak(at: now)
        let breakName = activeBreak?.name ?? "休息"
        let activeCount = p.breakPeriods.filter { $0.enabled }.count
        let breakTitle = activeBreak == nil ? "摸鱼进行中 🐟" : "休息中（" + breakName + "）🍚"
        return CountdownState(
            phase: .working, title: breakTitle,
            label: "距离下班还有", digits: digits(remain), progress: progress,
            sub: "已工作 \(human(elapsed)) · 今日共 \(human(total))" +
                 (activeCount > 0 ? "（已扣 \(activeCount) 段休息）" : ""),
            quote: activeBreak != nil ? pick(QUOTES["break"]!, now) : workingQuote(remain, now),
            menu: activeBreak != nil ? "🍚 休息中" : "🕕 \(digits(remain))",
            menuShort: activeBreak != nil ? "休息" : shortMinutes(digits(remain)))
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
            quote: off > 4 * 3600 ? pick(QUOTES["late"]!, now) : pick(QUOTES["off"]!, now),
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

