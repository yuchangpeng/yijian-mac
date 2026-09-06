import AppKit
import ApplicationServices

struct GrabContext {
    enum Mode { case selection, wholeField }
    enum Source { case ax, clipboard }

    let text: String
    let mode: Mode
    let source: Source
    let app: NSRunningApplication?
    let axElement: AXUIElement?
    let selectedRange: CFRange?
    let caretRect: NSRect? // Cocoa 坐标
    /// 抓取时我们主动做了 ⌘A 全选(取消时要把选区收起,防止用户接着打字覆盖原文)
    let autoSelectedAll: Bool
}

enum GrabOutcome {
    case ok(GrabContext)
    case fail(String)
}

enum TextGrabber {
    static let maxGrabLength = 3000

    /// 这些 App 的"焦点元素"是整个终端屏幕,整框抓取会拿到全部回滚缓冲,禁止
    private static let blockedBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
    ]
    /// 兜底路径的自动 ⌘A 额外排除 Finder(⌘A/⌘C 会复制文件而非文字)
    private static let selectAllBlockedBundles: Set<String> =
        blockedBundles.union(["com.apple.finder"])

    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox",
    ]

    @MainActor
    static func grab() async -> GrabOutcome {
        let app = NSWorkspace.shared.frontmostApplication
        let pid = app?.processIdentifier

        var element = focusedElement(appPID: pid)
        if element == nil, let pid {
            // Chromium/Electron 系 App 默认关闭辅助功能树,主动唤醒后重试一次
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            try? await Task.sleep(nanoseconds: 200_000_000)
            element = focusedElement(appPID: pid)
            Log.grab.info("AX wake-up retry, element found=\(element != nil)")
        }

        let bundleID = app?.bundleIdentifier ?? ""
        var caret: NSRect?
        var storedRange: CFRange?
        let windowRect = pid.flatMap { focusedWindowRect(pid: $0) }

        // 部分 Electron/Chromium App 返回的 AX 坐标是相对窗口而非全局屏幕的;
        // 凡是中心点落在焦点窗口范围之外的矩形一律视为不可信
        func plausible(_ rect: NSRect) -> Bool {
            guard let win = windowRect else { return true }
            return NSPointInRect(NSPoint(x: rect.midX, y: rect.midY), win.insetBy(dx: -16, dy: -16))
        }

        if let el = element {
            let role = stringAttribute(el, kAXRoleAttribute) ?? "?"
            if role == "AXSecureTextField" {
                return .fail("出于安全考虑,不读取密码输入框")
            }
            storedRange = rangeAttribute(el, kAXSelectedTextRangeAttribute)
            // 定位链:精确光标 → 小尺寸输入框的下沿(均需通过窗口范围校验)
            let fieldFrame = frameRect(of: el).flatMap { plausible($0) ? $0 : nil }
            caret = caretRect(of: el, range: storedRange).flatMap { plausible($0) ? $0 : nil }
            if let c = caret, let f = fieldFrame,
               abs(c.minX - f.minX) < 4, abs(c.minY - f.minY) < 4, abs(c.height - f.height) < 8 {
                // 有的 App 把整个元素框当作光标矩形返回,不可信,丢弃
                caret = nil
            }
            if caret == nil, let f = fieldFrame, f.height <= 320 {
                // 只有"像输入框"的小元素才挂它下沿;窗口级大容器会把面板带到屏幕角落
                caret = NSRect(x: f.minX + 4, y: f.minY, width: 0, height: f.height)
            }
            Log.grab.log("anchor: caret=\(caret.map(String.init(describing:)) ?? "nil", privacy: .public) window=\(windowRect.map(String.init(describing:)) ?? "nil", privacy: .public)")

            // 选中了 → 只翻译选中部分
            if let selected = stringAttribute(el, kAXSelectedTextAttribute),
               !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Log.grab.info("AX selection grab: role=\(role, privacy: .public) len=\(selected.count)")
                return .ok(GrabContext(text: selected, mode: .selection, source: .ax, app: app,
                                       axElement: el, selectedRange: storedRange, caretRect: caret,
                                       autoSelectedAll: false))
            }

            // 没选中 → 取整框全部翻译。角色白名单之外,凡是有"选区"概念的元素也视为可编辑文本
            let editable = editableRoles.contains(role) || storedRange != nil
            if editable, !blockedBundles.contains(bundleID),
               let value = stringAttribute(el, kAXValueAttribute),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               value.count <= maxGrabLength {
                Log.grab.info("AX whole-field grab: role=\(role, privacy: .public) len=\(value.count)")
                return .ok(GrabContext(text: value, mode: .wholeField, source: .ax, app: app,
                                       axElement: el, selectedRange: storedRange, caretRect: caret,
                                       autoSelectedAll: false))
            }
            Log.grab.info("AX no text: role=\(role, privacy: .public), falling back to clipboard")
        } else {
            Log.grab.info("AX focused element unavailable, falling back to clipboard")
        }

        // 定位链兜底:焦点窗口底部居中(聊天类输入框都在窗口底部,位置贴近打字处
        // 且完全可预期;不跟随鼠标)
        if caret == nil, let win = windowRect {
            caret = NSRect(x: win.midX - 190, y: min(win.minY + 300, win.midY), width: 0, height: 0)
        }

        // 剪贴板兜底(微信/Electron 等辅助功能读不到的 App):
        // 先 ⌘C 抓选中;没选中就自动 ⌘A 全选再抓,整框替换(Finder/终端除外)
        let allowSelectAll = !selectAllBlockedBundles.contains(bundleID)
        if let result = await ClipboardGrabber.grab(allowSelectAll: allowSelectAll) {
            if result.usedSelectAll && result.text.count > maxGrabLength {
                // 太长不翻;把我们造成的全选收起,防止用户接着打字覆盖原文
                KeyPoster.post(KeyPoster.keyRight)
                return .fail("内容超过 \(maxGrabLength) 字:请选中要翻译的部分")
            }
            Log.grab.info("clipboard fallback grab len=\(result.text.count) selectAll=\(result.usedSelectAll)")
            return .ok(GrabContext(text: result.text,
                                   mode: result.usedSelectAll ? .wholeField : .selection,
                                   source: .clipboard, app: app,
                                   axElement: element, selectedRange: storedRange, caretRect: caret,
                                   autoSelectedAll: result.usedSelectAll))
        }

        return .fail("没有取到文字:请先点击要翻译的输入框")
    }

    // MARK: - AX helpers

    /// 焦点元素:先查 system-wide,失败再查 App 级(部分 App 只响应后者)
    private static func focusedElement(appPID pid: pid_t?) -> AXUIElement? {
        var ref: CFTypeRef?
        let systemWide = AXUIElementCreateSystemWide()
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
           let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() {
            return (r as! AXUIElement)
        }
        guard let pid else { return nil }
        ref = nil
        let axApp = AXUIElementCreateApplication(pid)
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
           let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() {
            return (r as! AXUIElement)
        }
        return nil
    }

    private static func stringAttribute(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func rangeAttribute(_ el: AXUIElement, _ attr: String) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &range) else { return nil }
        return range
    }

    /// 元素(输入框/窗口)的屏幕矩形,Cocoa 坐标
    private static func frameRect(of el: AXUIElement) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = posRef, CFGetTypeID(p) == AXValueGetTypeID(),
              let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((p as! AXValue), .cgPoint, &point),
              AXValueGetValue((s as! AXValue), .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoaY = primary.frame.maxY - (point.y + size.height)
        return NSRect(x: point.x, y: cocoaY, width: size.width, height: size.height)
    }

    /// 前台 App 焦点窗口的屏幕矩形(剪贴板兜底路径的定位用)
    private static func focusedWindowRect(pid: pid_t) -> NSRect? {
        let axApp = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let w = winRef, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return frameRect(of: (w as! AXUIElement))
    }

    /// 光标(或选区起点)的屏幕矩形,Cocoa 坐标;Electron/网页常拿不到,返回 nil 由调用方兜底
    private static func caretRect(of el: AXUIElement, range: CFRange?) -> NSRect? {
        guard var r = range else { return nil }
        if r.length == 0 { r = CFRange(location: max(0, r.location - 1), length: 1) }
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef) == .success,
              let bv = boundsRef, CFGetTypeID(bv) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue((bv as! AXValue), .cgRect, &rect),
              rect != .zero, rect.width.isFinite, rect.height.isFinite else { return nil }
        // Quartz(主屏左上原点)→ Cocoa(左下原点)
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoaY = primary.frame.maxY - rect.maxY
        return NSRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
    }
}
