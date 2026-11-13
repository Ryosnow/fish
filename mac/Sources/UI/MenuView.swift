// 设置面板：三个 Tab 与分组内容

import AppKit
import SwiftUI

/// 三个 Tab 收敛设置项（渐进式披露：低频项进「高级」折叠）
struct MenuView: View {
    @EnvironmentObject var store: Store

    private let dayLabels = [1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 0: "日"]
    private let dayOrder = [1, 2, 3, 4, 5, 6, 0]
    @State private var tab = 0
    @State private var pickedDate = Date()
    @ScaledMetric(relativeTo: .largeTitle) private var overviewDigits: CGFloat = 40
    @ScaledMetric(relativeTo: .title3) private var pctSize: CGFloat = 20

    // 通用作息规则的表单状态（时间均为中性默认值，用户自行填写）
    @State private var newScheduleName = ""
    @State private var newScheduleStart = dateFromHHMM("09:00")
    @State private var newScheduleEnd = dateFromHHMM("18:00")
    @State private var newRuleWeekday = 1
    @State private var newRuleScheduleId = ""
    @State private var newRuleStart = dateFromHHMM("09:00")
    @State private var newRuleEnd = dateFromHHMM("18:00")
    @State private var todayEnd = dateFromHHMM("18:00")

    private func todaySourceText(_ now: Date, _ p: Prefs) -> String {
        if p.dateOverrides[dayKey(now)] != nil { return "今天已临时调整，不影响其它日期" }
        let w = Calendar.current.component(.weekday, from: now) - 1
        if p.weekdayRules[String(w)] != nil { return "来自每周规则，自动生效" }
        return "跟随全局默认作息"
    }

    var body: some View {
        let st = store.state
        let color = paletteColor(store.prefs)
        return VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("总览").tag(0)
                Text("作息").tag(1)
                Text("周进度").tag(2)
                Text("显示").tag(3)
            }
            .labelsHidden().pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider()

            // 页面大标题（Cursor 设置页风格）
            HStack {
                Text(["总览", "作息", "周进度", "显示"][tab])
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)

            // 统一错误提示：放在 Tab 栏下方，任何 Tab 都能看到（登录自启失败发生在「显示 → 高级」）
            if let err = store.timeError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").imageScale(.small)
                    Text(err).font(.caption).lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        store.timeError = nil
                    } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭提示")
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.red.opacity(0.06))
                Divider()
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if tab == 0 {
                        overview(st: st, color: color)
                    } else if tab == 1 {
                        scheduleTab(color: color)
                    } else if tab == 2 {
                        weekTab(color: color)
                    } else {
                        appearance()
                    }
                }
                .padding(16)
                .frame(width: 298, alignment: .leading)
            }

            Divider()

            // 固定操作栏：只保留最高频的两项
            HStack(spacing: 8) {
                Button(store.isStealth ? "恢复显示" : "立即隐身") { store.toggleStealth() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 330, height: 480)
        .background(PanelColor.background)
        .preferredColorScheme(preferredScheme(store.prefs.theme))
    }

    // MARK: 总览

    private func overview(st: CountdownState, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(st.title).font(.headline)
                Spacer()
                Text("\(Calendar.current.component(.month, from: store.now))/\(Calendar.current.component(.day, from: store.now))")
                    .font(.caption).foregroundStyle(PanelColor.secondary)
            }

            DigitsText(st: st, size: overviewDigits, color: color)
            Text(st.label).font(.caption).foregroundStyle(PanelColor.secondary)

            let progress = displayProgress(store.now, store.prefs, st)
            HStack(spacing: 10) {
                ProgressBar(value: progress, color: color)
                Text(menuPercentText(progress: progress, isStealth: false,
                                     weekMode: store.prefs.progressMode == 1) ?? "")
                    .font(.system(size: pctSize, weight: .semibold, design: .monospaced))
                    .monospacedDigit().foregroundStyle(color)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            Text(st.sub).font(.caption).foregroundStyle(PanelColor.secondary).lineLimit(2)
            if store.prefs.progressMode == 1 {
                Text("进度口径：本周 · 悬浮窗仍显示当日进度")
                    .font(.caption).foregroundStyle(PanelColor.secondary)
            }

            // 默认收起；标题行仍显示当前生效的下班时间，不用展开也能看
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(todaySourceText(store.now, store.prefs))
                        .font(.caption).foregroundStyle(PanelColor.secondary)
                    HStack(spacing: 8) {
                        Menu("用方案调整") {
                            ForEach(store.prefs.schedules) { s in
                                Button(s.name) { store.setTodaySchedule(s.schedule) }
                            }
                        }
                        .disabled(store.prefs.schedules.isEmpty)
                        Button("恢复规则") { store.clearTodayOverride() }
                            .disabled(store.prefs.dateOverrides[dayKey(store.now)] == nil)
                    }
                    DisclosureGroup("自定义时间") {
                        HStack {
                            DatePicker("", selection: $todayEnd, displayedComponents: .hourAndMinute)
                                .labelsHidden().fixedSize()
                            Button("应用") {
                                let s = schedule(for: store.now, store.prefs)
                                store.setTodaySchedule(DaySchedule(s.start, hhmmString(todayEnd)))
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("今天下班时间").font(.subheadline)
                    Spacer()
                    Text(schedule(for: store.now, store.prefs).end)
                        .font(.subheadline).monospacedDigit()
                }
            }

            Divider()
            Text("⌃⌥⌘H 一键隐身 / 恢复 · 右键菜单栏可打开菜单")
                .font(.caption).foregroundStyle(PanelColor.secondary)
        }
    }

    // MARK: 作息

    private func scheduleTab(color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard("上下班时间") {
                HStack {
                    Text("上班").font(.subheadline).lineLimit(1).fixedSize()
                    Spacer()
                    DatePicker("", selection: Binding<Date>(
                        get: { dateFromHHMM(store.prefs.start) },
                        set: { store.setStart(hhmmString($0)) }
                    ), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                }
                .padding(.vertical, 6)
                CardSeparator()
                HStack {
                    Text("下班").font(.subheadline).lineLimit(1).fixedSize()
                    Spacer()
                    DatePicker("", selection: Binding<Date>(
                        get: { dateFromHHMM(store.prefs.end) },
                        set: { store.setEnd(hhmmString($0)) }
                    ), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                }
                .padding(.vertical, 6)
                if scheduleCrossesMidnight(for: store.now, store.prefs) {
                    let todaySched = schedule(for: store.now, store.prefs)
                    Text("跨零点班次：\(todaySched.start) → 次日 \(todaySched.end)")
                        .font(.caption).foregroundStyle(PanelColor.secondary)
                }
            }

            DisclosureGroup("作息方案与每周规则（高级）") {
                VStack(alignment: .leading, spacing: 12) {
                SettingsCard("作息方案") {
                    if store.prefs.schedules.isEmpty {
                        Text("还没有方案。添加常用作息后，配置每周规则或今天调整时可直接选用。")
                            .font(.caption).foregroundStyle(PanelColor.secondary)
                    } else {
                        ForEach(store.prefs.schedules) { s in
                            HStack(spacing: 8) {
                                Text(s.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text("\(s.start) – \(s.end)").font(.caption).monospacedDigit()
                                Button {
                                    store.removeSchedule(id: s.id)
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .buttonStyle(.plain).foregroundStyle(PanelColor.secondary)
                                .accessibilityLabel("删除方案 \(s.name)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    DisclosureGroup("添加方案") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("名称，如 早收工", text: $newScheduleName)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Text("上班").font(.caption).lineLimit(1).fixedSize()
                                DatePicker("", selection: $newScheduleStart, displayedComponents: .hourAndMinute)
                                    .labelsHidden().fixedSize()
                                Spacer()
                                Text("下班").font(.caption).lineLimit(1).fixedSize()
                                DatePicker("", selection: $newScheduleEnd, displayedComponents: .hourAndMinute)
                                    .labelsHidden().fixedSize()
                            }
                            Button("添加") {
                                let name = newScheduleName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                store.addSchedule(name: name,
                                                  start: hhmmString(newScheduleStart),
                                                  end: hhmmString(newScheduleEnd))
                                newScheduleName = ""
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                SettingsCard("每周规则") {
                    let keys = store.prefs.weekdayRules.keys.sorted()
                    if keys.isEmpty {
                        Text("未配置。可让某几天固定用另一套作息，其余跟随全局默认。")
                            .font(.caption).foregroundStyle(PanelColor.secondary)
                    } else {
                        ForEach(keys, id: \.self) { k in
                            let rule = store.prefs.weekdayRules[k]!
                            HStack(spacing: 8) {
                                Text("周\(dayLabels[Int(k) ?? 0] ?? k)").font(.subheadline)
                                Spacer()
                                Text("\(rule.start) – \(rule.end)").font(.caption).monospacedDigit()
                                Button {
                                    store.removeWeekdayRule(Int(k) ?? 0)
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .buttonStyle(.plain).foregroundStyle(PanelColor.secondary)
                                .accessibilityLabel("删除周\(dayLabels[Int(k) ?? 0] ?? k)规则")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    DisclosureGroup("添加规则") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("星期").font(.caption)
                                Picker("", selection: $newRuleWeekday) {
                                    ForEach(dayOrder, id: \.self) { d in
                                        Text("周\(dayLabels[d] ?? "")").tag(d)
                                    }
                                }
                                .labelsHidden().frame(width: 110)
                                Spacer()
                            }
                            HStack {
                                Text("方案").font(.caption)
                                Picker("", selection: $newRuleScheduleId) {
                                    Text("自定义时间").tag("")
                                    ForEach(store.prefs.schedules) { s in Text(s.name).tag(s.id) }
                                }
                                .labelsHidden().frame(width: 170)
                                Spacer()
                            }
                            if newRuleScheduleId.isEmpty {
                                HStack {
                                    Text("上班").font(.caption).lineLimit(1).fixedSize()
                                    DatePicker("", selection: $newRuleStart, displayedComponents: .hourAndMinute)
                                        .labelsHidden().fixedSize()
                                    Spacer()
                                    Text("下班").font(.caption).lineLimit(1).fixedSize()
                                    DatePicker("", selection: $newRuleEnd, displayedComponents: .hourAndMinute)
                                        .labelsHidden().fixedSize()
                                }
                            }
                            Button("添加规则") {
                                let s: DaySchedule
                                if let picked = store.prefs.schedules.first(where: { $0.id == newRuleScheduleId }) {
                                    s = picked.schedule
                                } else {
                                    s = DaySchedule(hhmmString(newRuleStart), hhmmString(newRuleEnd))
                                }
                                store.setWeekdayRule(newRuleWeekday, s)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                }
                .padding(.top, 8)
            }

            SettingsCard("工作日与午休") {
                HStack(spacing: 6) {
                    ForEach(dayOrder, id: \.self) { d in
                        let on = store.prefs.workdays.contains(d)
                        Button {
                            store.toggleDay(d)
                        } label: {
                            Text(dayLabels[d] ?? "")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(on ? color : Color.primary.opacity(0.08))
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("周\(dayLabels[d] ?? "")")
                        .accessibilityValue(on ? "已选" : "未选")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
                CardSeparator()
                CheckRow(title: "午休不计入进度", subtitle: "午休时间从工作时长中扣除", isOn: $store.prefs.breakEnabled)
                if store.prefs.breakEnabled {
                    HStack(spacing: 8) {
                        DatePicker("", selection: Binding<Date>(
                            get: { dateFromHHMM(store.prefs.breakStart ?? "12:00") },
                            set: { store.prefs.breakStart = hhmmString($0) }
                        ), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                        Text("至").font(.caption).foregroundStyle(PanelColor.secondary)
                            .lineLimit(1).fixedSize()
                        DatePicker("", selection: Binding<Date>(
                            get: { dateFromHHMM(store.prefs.breakEnd ?? "13:00") },
                            set: { store.prefs.breakEnd = hhmmString($0) }
                        ), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                        Spacer()
                    }
                }
            }
            .font(.caption)

            DisclosureGroup("节假日 / 调休（按日期覆盖）") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $pickedDate, displayedComponents: .date)
                            .labelsHidden().fixedSize()
                        Button("设为补班") { store.prefs.dayOverrides[dayKey(pickedDate)] = 1 }
                        Button("设为放假") { store.prefs.dayOverrides[dayKey(pickedDate)] = 0 }
                    }
                    if store.prefs.dayOverrides.isEmpty {
                        Text("调休补班日、法定假期逐日标记，优先级高于每周工作日。")
                            .font(.caption).foregroundStyle(PanelColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(store.prefs.dayOverrides.keys.sorted(), id: \.self) { key in
                            HStack(spacing: 6) {
                                Text(key).font(.caption).monospacedDigit()
                                Text(store.prefs.dayOverrides[key] == 1 ? "补班" : "放假")
                                    .font(.caption).foregroundStyle(PanelColor.secondary)
                                Spacer()
                                Button("移除") { store.prefs.dayOverrides.removeValue(forKey: key) }
                                    .buttonStyle(.borderless).font(.caption)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)

        }
    }

    // MARK: 周进度

    private func weekTab(color: Color) -> some View {
        let p = store.prefs
        let target = weekTargetSeconds(store.now, p)
        let worked = weekWorkedSeconds(store.now, p)
        let progress = weekProgress(store.now, p)
        return VStack(alignment: .leading, spacing: 12) {
            SettingsCard("进度口径") {
                Picker("", selection: $store.prefs.progressMode) {
                    Text("当日进度").tag(0)
                    Text("本周进度").tag(1)
                }
                .labelsHidden().pickerStyle(.segmented)
                Text("切换后菜单栏圆环与百分比按所选口径显示；悬浮窗始终显示当日进度。")
                    .font(.caption).foregroundStyle(PanelColor.secondary)
            }

            SettingsCard("每周总工时") {
                CheckRow(title: "手动指定固定工时", subtitle: "关闭时按本周作息规则自动求和",
                         isOn: Binding<Bool>(
                            get: { p.weeklyTargetHours != nil },
                            set: { store.prefs.weeklyTargetHours = $0 ? 45 : nil }
                         ))
                if let hours = p.weeklyTargetHours {
                    Stepper(value: Binding<Double>(
                        get: { store.prefs.weeklyTargetHours ?? 45 },
                        set: { store.prefs.weeklyTargetHours = $0 }
                    ), in: 1...80, step: 0.5) {
                        Text(String(format: "%.1f 小时", hours))
                            .font(.subheadline).monospacedDigit()
                    }
                } else {
                    Text("自动：按本周每天作息规则求和（含调休与补班），切换作息后自动更新。当前 \(String(format: "%.1f", target / 3600)) 小时。")
                        .font(.caption).foregroundStyle(PanelColor.secondary)
                }
            }

            SettingsCard("本周进度") {
                HStack {
                    Text("累计净工时").font(.subheadline)
                    Spacer()
                    Text(human(worked)).font(.subheadline)
                }
                CardSeparator()
                HStack {
                    Text("目标").font(.subheadline)
                    Spacer()
                    Text(human(target)).font(.subheadline)
                }
                CardSeparator()
                HStack {
                    Text("剩余").font(.subheadline)
                    Spacer()
                    Text(human(max(0, target - worked))).font(.subheadline)
                }
                CardSeparator()
                HStack {
                    Text("进度").font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f%%", progress * 100))
                        .font(.subheadline).monospacedDigit()
                }
                ProgressBar(value: progress, color: color)
            }
        }
    }

    // MARK: 显示

    private func appearance() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard("悬浮窗") {
                CheckRow(title: "显示悬浮窗", subtitle: "在桌面上显示倒计时小窗", isOn: $store.prefs.showPanel)
                CardSeparator()
                CheckRow(title: "紧凑模式", subtitle: "只保留倒计时，隐藏进度与语录", isOn: $store.prefs.compact)
            }

            SettingsCard("菜单栏") {
                HStack {
                    Text("样式").font(.subheadline)
                    Spacer()
                    Picker("", selection: $store.prefs.menuStyle) {
                        Text("完整").tag(0)
                        Text("精简").tag(1)
                        Text("进度环").tag(2)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 168)
                }
                .padding(.vertical, 8)
                CardSeparator()
                CheckRow(title: "显示百分比", subtitle: "菜单栏显示工作进度百分比", isOn: $store.prefs.menuPercent)
                    .disabled(store.prefs.menuStyle != 2)
            }

            SettingsCard("外观") {
                HStack {
                    Text("主题").font(.subheadline)
                    Spacer()
                    Picker("", selection: $store.prefs.theme) {
                        Text("跟随系统").tag(0)
                        Text("深色").tag(1)
                        Text("浅色").tag(2)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 168)
                }
                .padding(.vertical, 8)
                CardSeparator()
                HStack(spacing: 10) {
                    Text("透明度").font(.subheadline)
                    Slider(value: $store.prefs.panelOpacity, in: 0.4...1.0)
                    Text("\(Int(store.prefs.panelOpacity * 100))%")
                        .font(.caption).monospacedDigit().foregroundStyle(PanelColor.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }

            DisclosureGroup("高级") {
                VStack(alignment: .leading, spacing: 0) {
                    CheckRow(title: "总在最前", subtitle: "悬浮窗始终位于其他窗口之上", isOn: $store.prefs.alwaysOnTop)
                    CardSeparator()
                    CheckRow(title: "下班提示音", subtitle: "到点播放提示音", isOn: $store.prefs.sound)
                    CardSeparator()
                    CheckRow(title: "登录时启动", subtitle: "登录 macOS 后自动启动", isOn: Binding<Bool>(
                        get: { store.prefs.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                    HStack(spacing: 8) {
                        Button(store.prefs.collapsed ? "展开悬浮窗" : "收缩悬浮窗") {
                            store.prefs.collapsed.toggle()
                        }
                        Button("隐身 30 分") { store.stealthFor(minutes: 30) }
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
        .font(.caption)
    }
}

