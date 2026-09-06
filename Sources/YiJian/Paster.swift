import AppKit
import ApplicationServices

struct ReplacementRecord {
    let originalText: String
    let translatedText: String
    let context: GrabContext
}

enum Paster {
    /// 从剪贴板历史粘贴:选中的条目提升为当前剪贴板内容(不恢复旧内容,这是剪贴板管理器的惯例)
    @MainActor
    static func pasteHistoryItem(_ text: String, into app: NSRunningApplication?) async {
        _ = app?.activate()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        KeyPoster.post(KeyPoster.keyV, flags: .maskCommand)
        Log.paste.info("pasted history item len=\(text.count)")
    }

    /// 把译文回填到原输入框(面板必须已 orderOut,否则 ⌘V 会被面板自己吃掉)
    @MainActor
    static func replace(with translation: String, context: GrabContext) async {
        ClipboardStore.shared.suppress(for: 2.0)
        _ = context.app?.activate()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let saved = Pasteboard.snapshot()
        let ourChange = Pasteboard.setTransientString(translation)

        if context.mode == .wholeField {
            KeyPoster.post(KeyPoster.keyA, flags: .maskCommand)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        KeyPoster.post(KeyPoster.keyV, flags: .maskCommand)
        Log.paste.info("pasted translation len=\(translation.count) mode=\(String(describing: context.mode), privacy: .public)")

        // 等目标 App 读完剪贴板再恢复;若期间被第三方改过就不动
        try? await Task.sleep(nanoseconds: 800_000_000)
        if NSPasteboard.general.changeCount == ourChange {
            Pasteboard.restore(saved)
        }
    }

    /// 还原上次替换。返回 true 表示已自动粘贴还原;false 表示只把原文放进了剪贴板
    @MainActor
    static func revert(_ record: ReplacementRecord) async -> Bool {
        ClipboardStore.shared.suppress(for: 2.0)
        let ctx = record.context
        _ = ctx.app?.activate()
        try? await Task.sleep(nanoseconds: 150_000_000)

        switch ctx.mode {
        case .wholeField:
            KeyPoster.post(KeyPoster.keyA, flags: .maskCommand)
            try? await Task.sleep(nanoseconds: 80_000_000)
        case .selection:
            // 尝试用 AX 重建覆盖译文的选区(AX range 按 UTF-16 计)
            guard let el = ctx.axElement, let range = ctx.selectedRange else {
                Pasteboard.setTransientString(record.originalText)
                return false
            }
            var newRange = CFRange(location: range.location, length: record.translatedText.utf16.count)
            guard let value = AXValueCreate(.cfRange, &newRange),
                  AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
                Pasteboard.setTransientString(record.originalText)
                return false
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        let saved = Pasteboard.snapshot()
        let ourChange = Pasteboard.setTransientString(record.originalText)
        KeyPoster.post(KeyPoster.keyV, flags: .maskCommand)
        Log.paste.info("reverted last replacement")

        try? await Task.sleep(nanoseconds: 800_000_000)
        if NSPasteboard.general.changeCount == ourChange {
            Pasteboard.restore(saved)
        }
        return true
    }
}
