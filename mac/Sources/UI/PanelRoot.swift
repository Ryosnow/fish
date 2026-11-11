// 悬浮窗内容：完整态 / 收缩态与右键菜单

import AppKit
import SwiftUI

/// 悬浮窗内容：可收缩成一个不显示任何数字的小图标
struct PanelRoot: View {
    @EnvironmentObject var store: Store

    // Dynamic Type：大号倒计时随系统字号缩放，不再写死 pt
    @ScaledMetric(relativeTo: .largeTitle) private var largeDigits: CGFloat = 42
    @ScaledMetric(relativeTo: .title2) private var compactDigits: CGFloat = 30

    var body: some View {
        let p = store.prefs
        let width: CGFloat? = p.collapsed ? nil : (p.compact ? 200 : 300)
        let corner: CGFloat = p.collapsed ? 12 : 18
        return Group {
            if p.collapsed {
                miniView
            } else {
                fullView(st: store.state, p: p, color: paletteColor(p))
            }
        }
        .padding(.horizontal, p.collapsed ? 0 : 16)
        .padding(.vertical, p.collapsed ? 0 : 12)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(PanelColor.background)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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
        Button {
            store.prefs.collapsed = false
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock").font(.body)
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(PanelColor.secondary)
            }
            .frame(width: 46, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击展开；右键可完全隐身")
        .accessibilityLabel("展开倒计时")
        .accessibilityHint("展开后显示完整倒计时")
    }

    private func fullView(st: CountdownState, p: Prefs, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(st.title).font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    store.prefs.collapsed = true
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PanelColor.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .opacity(0.5)
                .help("收缩成一个小图标（不显示倒计时）")
            }
            .padding(.bottom, p.compact ? 5 : 8)

            DigitsText(st: st, size: p.compact ? compactDigits : largeDigits, color: color)
                .padding(.bottom, p.compact ? 2 : 8)

            if !p.compact {
                ProgressBar(value: st.progress, color: color)
                HStack {
                    Text(st.label).font(.caption)
                    Spacer()
                    Text("\(Int(st.progress * 100))%").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(PanelColor.secondary)
                .padding(.top, 5)

                Text(st.sub).font(.caption).foregroundStyle(PanelColor.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                Text(st.quote).font(.footnote).lineLimit(2).padding(.top, 5)
            }
        }
    }
}

/// 点击菜单栏弹出的主面板：详情 + 设置
