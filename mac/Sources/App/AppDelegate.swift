// 应用生命周期：菜单栏、Popover、面板、热键与设置联动

import AppKit
import SwiftUI
import Combine
import ServiceManagement
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
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
    private var currentPercentShown = true
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

        // 开机时校正一次登录自启开关，避免与系统设置里的实际状态脱节
        store.syncLaunchAtLogin()

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

    /// 三档统一用系统 button；切换档位或百分比开关时重建整个 item
    private func rebuildStatusItem(style: Int) {
        if style != 2 {
            rebuildAsButton(style: style)
            return
        }
        if let old = statusItem { NSStatusBar.system.removeStatusItem(old) }
        currentMenuStyle = style
        let showPct = store.prefs.menuPercent
        let width: CGFloat = showPct ? 58 : 20
        currentPercentShown = showPct
        statusItem = NSStatusBar.system.statusItem(withLength: width)
        // 关键：继续用系统 NSStatusBarButton，点击反馈 / 高亮 / 菜单全部由系统绘制，
        // 自定义绘制只作为它的子视图（hitTest 返回 nil，事件仍落到 button）。
        guard let button = statusItem.button else {
            ringUnavailable = true
            rebuildAsButton(style: 1)
            return
        }
        button.title = ""
        button.image = nil
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "下班倒计时（左键打开面板，右键菜单）"

        let v = RingStatusView(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        v.showPercent = showPct
        v.autoresizingMask = [.width, .height]
        button.addSubview(v)
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
        popover.contentSize = NSSize(width: 330, height: 480)
        popover.delegate = self
    }

    // 让系统按钮在面板打开期间保持高亮（颜色 / 圆角 / 尺寸全由系统绘制）
    func popoverDidShow(_ notification: Notification) {
        statusItem?.button?.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
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
        // 百分比开关会改变视图宽度，需要重建 statusItem
        let pctChanged = effective == 2 && store.prefs.menuPercent != currentPercentShown
        if effective != currentMenuStyle || statusItem == nil || pctChanged {
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
            v.showPercent = store.prefs.menuPercent
            statusItem?.length = store.prefs.menuPercent ? 58 : 20
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
        // 每次打开面板都校正一次：用户可能刚在系统设置里增删过登录项
        store.syncLaunchAtLogin()
        NSApp.activate(ignoringOtherApps: true)
        // 系统按钮始终存在，用它定位 popover（箭头对齐更准）
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else if let v = ringView {
            popover.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
        }
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

