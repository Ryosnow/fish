import AppKit
import Carbon

// MARK: - 启动入口与命令行自检
// 说明：Swift 规定顶层可执行语句只能出现在 main.swift；其余文件只放声明。
// 拆分后全局常量由编译器按需惰性初始化，不再有原来「按源码顺序初始化」的陷阱。

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
if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
