// 纯函数回归自测（--selftest）

import Foundation
import AppKit

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
    // 正红：G/B 相等（不偏橙也不偏粉），且与 R 差距足够大
    check("红色为正红不偏粉",
          d100.map { abs($0.g - $0.b) < 0.01 && $0.r - $0.g > 0.7 } ?? false, "")
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

    check("菜单栏百分比 clamp",
          menuPercentText(progress: 0.42, isStealth: false) == "42%" &&
          menuPercentText(progress: 2, isStealth: false) == "100%" &&
          menuPercentText(progress: -1, isStealth: false) == "0%", "")
    check("菜单栏隐身隐藏百分比", menuPercentText(progress: 0.5, isStealth: true) == nil, "")
    // 58pt 项宽下右对齐的 "100%" 不能侵入左侧环区域（环右缘约 18pt）
    let pctFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)
    let pctWidth = ("100%" as NSString).size(withAttributes: [.font: pctFont]).width
    let pctX = round(58 - 2 - pctWidth)
    check("百分比文字右对齐不越界", pctX >= 19 && pctX + pctWidth <= 57,
          "x=\(Int(pctX)) w=\(Int(pctWidth))")

    let oldJSON = "{\"start\":\"09:30\",\"end\":\"19:00\",\"compact\":true}".data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(Prefs.self, from: oldJSON)
    check("旧配置向后兼容", decoded?.start == "09:30" && decoded?.palette == 0
          && decoded?.dayOverrides.isEmpty == true && decoded?.stealth == false, "")

    check("登录自启状态同步 任一启用即为开",
          launchAtLoginEnabled(systemRegistered: true, plistExists: false)
          && launchAtLoginEnabled(systemRegistered: false, plistExists: true)
          && !launchAtLoginEnabled(systemRegistered: false, plistExists: false), "")

    if failures > 0 { print("SELFTEST FAILED: \(failures) case(s)"); exit(1) }
    print("SELFTEST PASSED (38 cases)")
}

