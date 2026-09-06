import AppKit
import Carbon.HIToolbox

/// 全局热键(Carbon RegisterEventHotKey,无需辅助功能权限),支持多个热键按 id 分发
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    static let optionCommand = UInt32(cmdKey | optionKey)
    static let keyT: UInt32 = 17
    static let keyV: UInt32 = 9

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var installed = false

    private init() {}

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        handlers[id] = handler

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x594A_4B31), id: id) // "YJK1"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if status != noErr {
            Log.app.error("RegisterEventHotKey id=\(id) failed: \(status)")
        }
        hotKeyRefs.append(ref)
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async { manager.handlers[id]?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
    }
}
