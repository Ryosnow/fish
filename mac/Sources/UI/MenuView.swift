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

    var body: some View {
        let st = store.state
        let color = paletteColor(store.prefs)
        return VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("总览").tag(0)
                Text("作息").tag(1)
                Text("显示").tag(2)
            }
            .labelsHidden().pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider()

            // 页面大标题（Cursor 设置页风格）
            HStack {
                Text(["总览", "作息", "显示"][tab])
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
                        schedule(color: color)
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
        .frame(width: 330, height: 440)
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

            HStack(spacing: 10) {
                ProgressBar(value: st.progress, color: color)
                Text("\(Int(st.progress * 100))%")
                    .font(.system(size: pctSize, weight: .semibold, design: .monospaced))
                    .monospacedDigit().foregroundStyle(color)
                    .frame(minWidth: 54, alignment: .trailing)
            }
            Text(st.sub).font(.caption).foregroundStyle(PanelColor.secondary).lineLimit(2)

            Divider()
            Text("⌃⌥⌘H 一键隐身 / 恢复 · 右键菜单栏可打开菜单")
                .font(.caption).foregroundStyle(PanelColor.secondary)
        }
    }

    // MARK: 作息

    private func schedule(color: Color) -> some View {
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
                if isCrossMidnight(store.prefs) {
                    Text("跨零点班次：\(store.prefs.start) → 次日 \(store.prefs.end)")
                        .font(.caption).foregroundStyle(PanelColor.secondary)
                }
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

