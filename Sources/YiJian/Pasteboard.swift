import AppKit

enum Pasteboard {
    /// 剪贴板管理器约定:带此类型的条目不入历史
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func snapshot() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    /// 写入字符串并标记 transient,返回写入后的 changeCount
    @discardableResult
    static func setTransientString(_ string: String) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        item.setData(Data(), forType: transientType)
        pb.writeObjects([item])
        return pb.changeCount
    }
}

enum KeyPoster {
    // 虚拟键码:A=0, C=8, V=9, →=124
    static let keyA = 0
    static let keyC = 8
    static let keyV = 9
    static let keyRight = 124

    static func post(_ keyCode: Int, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum ClipboardGrabber {
    struct Result {
        let text: String
        let usedSelectAll: Bool
    }

    /// 模拟 ⌘C 抓选中文字;没选中且 allowSelectAll 时再 ⌘A 全选抓整框。读完恢复原剪贴板
    @MainActor
    static func grab(allowSelectAll: Bool) async -> Result? {
        ClipboardStore.shared.suppress(for: 3.0)
        let pb = NSPasteboard.general
        let saved = Pasteboard.snapshot()

        // 稍等,避免用户尚未松开的 ⌥⌘ 物理修饰键混进合成按键
        try? await Task.sleep(nanoseconds: 120_000_000)

        var result: Result?
        if let text = await copyAndRead(pb) {
            result = Result(text: text, usedSelectAll: false)
        } else if allowSelectAll {
            KeyPoster.post(KeyPoster.keyA, flags: .maskCommand)
            try? await Task.sleep(nanoseconds: 80_000_000)
            if let text = await copyAndRead(pb) {
                result = Result(text: text, usedSelectAll: true)
            }
        }
        Pasteboard.restore(saved)
        return result
    }

    private static func copyAndRead(_ pb: NSPasteboard) async -> String? {
        let before = pb.changeCount
        KeyPoster.post(KeyPoster.keyC, flags: .maskCommand)
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != before {
                guard let text = pb.string(forType: .string),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return text
            }
        }
        return nil
    }
}
