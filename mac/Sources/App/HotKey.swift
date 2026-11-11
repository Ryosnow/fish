// 全局热键：⌃⌥⌘H，任何应用前台都能一键隐身 / 恢复（不需要辅助功能权限）

import AppKit
import Carbon

// 全局热键：⌃⌥⌘H，任何应用前台都能一键隐身 / 恢复（不需要辅助功能权限）
private var globalHotKeyAction: (() -> Void)?
private var hotKeyRef: EventHotKeyRef?
private var eventHandlerRef: EventHandlerRef?

func registerGlobalHotKey(_ action: @escaping () -> Void) -> OSStatus {
    globalHotKeyAction = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
        DispatchQueue.main.async { globalHotKeyAction?() }
        return noErr
    }, 1, &spec, nil, &eventHandlerRef)
    guard installed == noErr else { return installed }
    let id = EventHotKeyID(signature: OSType(0x4F574348), id: 1) // 'OWCH'
    return RegisterEventHotKey(UInt32(kVK_ANSI_H),
                               UInt32(controlKey | optionKey | cmdKey),
                               id, GetApplicationEventTarget(), 0, &hotKeyRef)
}
