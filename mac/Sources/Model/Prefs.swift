// 偏好设置模型与持久化解码（向后兼容）

import Foundation

/// 一天的作息值（规则里直接存值，不引用方案 id）
struct DaySchedule: Codable, Equatable {
    var start: String
    var end: String
    init(_ start: String, _ end: String) { self.start = start; self.end = end }
}

/// 用户命名的作息方案，纯模板：配置规则时把值拷进规则
struct WorkSchedule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var start: String
    var end: String
    var schedule: DaySchedule { DaySchedule(start, end) }   // 计算属性，不参与 Codable
}

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
    // 以下两个字段已废弃：仅保留以兼容旧配置，界面不再提供配色自定义
    var palette: Int = 0
    var customHex: String = "#7C93A8"
    var collapsed: Bool = false           // 悬浮窗收缩成小图标
    var stealth: Bool = false             // 完全隐身
    var stealthUntil: Double? = nil       // 临时隐身到期时间
    var breakEnabled: Bool = false        // 午休不计入工作进度
    var breakStart: String? = "12:00"
    var breakEnd: String? = "13:00"
    var dayOverrides: [String: Int] = [:] // "yyyy-MM-dd": 1 补班 / 0 放假
    // 通用作息规则：方案库 / 星期规则 / 日期覆盖（旧配置缺省时为空，行为不变）
    var schedules: [WorkSchedule] = []
    var weekdayRules: [String: DaySchedule] = [:]  // "0"=日 ... "6"=六
    var dateOverrides: [String: DaySchedule] = [:] // "yyyy-MM-dd"
    var menuStyle: Int = 2               // 菜单栏：0 完整 / 1 精简 / 2 进度环（默认）
    var menuPercent: Bool = true         // 进度环右侧显示百分比进度

    private enum CodingKeys: String, CodingKey {
        case start, end, workdays, showPanel, compact, alwaysOnTop, sound, theme,
             launchAtLogin, panelOpacity, panelOrigin, palette, customHex,
             collapsed, stealth, stealthUntil, breakEnabled, breakStart, breakEnd,
             dayOverrides, schedules, weekdayRules, dateOverrides, menuStyle, menuPercent
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
        schedules = try c.decodeIfPresent([WorkSchedule].self, forKey: .schedules) ?? []
        weekdayRules = try c.decodeIfPresent([String: DaySchedule].self, forKey: .weekdayRules) ?? [:]
        dateOverrides = try c.decodeIfPresent([String: DaySchedule].self, forKey: .dateOverrides) ?? [:]
        menuStyle = try c.decodeIfPresent(Int.self, forKey: .menuStyle) ?? 2
        menuPercent = try c.decodeIfPresent(Bool.self, forKey: .menuPercent) ?? true
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
        // 通用作息规则：校验 HH:mm 与 key，非法项直接剔除，回落全局默认
        func validTime(_ s: String) -> Bool {
            let t = hhmm(s)
            return t.0 >= 0 && t.0 < 24 && t.1 >= 0 && t.1 < 60
        }
        p.schedules = p.schedules.filter {
            !$0.id.isEmpty && !$0.name.isEmpty && validTime($0.start) && validTime($0.end)
        }
        p.weekdayRules = p.weekdayRules.filter {
            guard let w = Int($0.key), (0...6).contains(w) else { return false }
            return validTime($0.value.start) && validTime($0.value.end)
        }
        p.dateOverrides = p.dateOverrides.filter {
            $0.key.count == 10 && validTime($0.value.start) && validTime($0.value.end)
        }
        if p.menuStyle < 0 || p.menuStyle > 2 { p.menuStyle = 2 }
        return p
    }
}

