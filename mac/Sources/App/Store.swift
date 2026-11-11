// 数据仓库：偏好发布、登录自启同步与状态派生

import AppKit
import Combine
import ServiceManagement

/// 纯函数：系统注册成功或回退 LaunchAgent 存在，任一为真即视为已启用登录自启
func launchAtLoginEnabled(systemRegistered: Bool, plistExists: Bool) -> Bool {
    systemRegistered || plistExists
}

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

    /// 从系统真实状态校正开关：用户可能在「系统设置 → 通用 → 登录项」手动改过。
    /// 只读不写系统状态；失败（plist 不可读）按未启用处理。
    func syncLaunchAtLogin() {
        var registered = false
        if #available(macOS 13.0, *) {
            registered = (SMAppService.mainApp.status == .enabled)
        }
        let path = NSHomeDirectory() + "/Library/LaunchAgents/com.rumor.offwork-countdown.plist"
        let plistExists = FileManager.default.fileExists(atPath: path)
        let actual = launchAtLoginEnabled(systemRegistered: registered, plistExists: plistExists)
        if prefs.launchAtLogin != actual { prefs.launchAtLogin = actual }
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

