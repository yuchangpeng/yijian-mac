import AppKit
import SwiftUI

/// 无边框面板要成为 key window 必须子类化
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSImage {
    /// 可拉伸的圆角蒙版(NSVisualEffectView 圆角的推荐做法,边缘抗锯齿、阴影贴合)
    static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// 液态玻璃浮动面板基类:窗口配置、定位、淡入淡出、键盘监视。
/// 子类通过 attach(rootView:) 装内容,override handleKey(_:) 消费按键。
@MainActor
class GlassPanelController: NSObject, NSWindowDelegate {
    private(set) var panel: KeyPanel!
    private var hosting: NSView!
    private var currentMaterialKey: String?
    private var keyMonitor: Any?
    private let width: CGFloat

    var anchorTop: NSPoint = .zero // 面板左上角锚点(Cocoa 坐标)
    var caret: NSRect?

    init(width: CGFloat) {
        self.width = width
        super.init()
    }

    var isVisible: Bool { panel.isVisible }

    func attach(rootView: some View) {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        hosting = NSHostingView(rootView: rootView)
        self.panel = panel
        rebuildBackdropIfNeeded()
    }

    /// 按设置里的「浮窗材质」构建/切换背板,下次弹出即生效
    private func rebuildBackdropIfNeeded() {
        let material = SettingsStore.panelMaterial
        guard material.rawValue != currentMaterialKey else { return }
        currentMaterialKey = material.rawValue
        hosting.removeFromSuperview()

        switch material {
        case .glassClear, .glassRegular:
            let glass = NSGlassEffectView()
            glass.cornerRadius = 22
            glass.style = material == .glassClear ? .clear : .regular
            glass.contentView = hosting
            panel.contentView = glass
        case .frosted:
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = .roundedCornerMask(radius: 22)
            panel.contentView = effect
            hosting.frame = effect.bounds
            hosting.autoresizingMask = [.width, .height]
            effect.addSubview(hosting)
        }
    }

    // MARK: - 显示 / 隐藏

    /// 设定锚点(caret 为空则跟随鼠标)并摆好位置,再 present
    func moveTo(caret: NSRect?) {
        self.caret = caret
        anchorTop = computeAnchor()
        positionPanel()
    }

    func present(makeKey: Bool) {
        rebuildBackdropIfNeeded()
        // 柔和入场:从上方 10pt 轻轻落下 + 淡入
        let finalFrame = panel.frame
        var startFrame = finalFrame
        startFrame.origin.y += 10
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
            installMonitor()
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.panel.invalidateShadow()
        })
    }

    func hide() {
        removeMonitor()
        panel.orderOut(nil)
        didHide()
    }

    /// 子类清理钩子
    func didHide() {}

    /// 子类处理按键;返回 true 表示已消费
    func handleKey(_ event: NSEvent) -> Bool { false }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - 键盘监视

    private func installMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - 定位

    private func computeAnchor() -> NSPoint {
        if let caret {
            return NSPoint(x: caret.minX, y: caret.minY - 10)
        }
        // 最终兜底:主屏中上位置,固定可预期(不跟随鼠标乱跑)
        let vis = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: vis.midX - width / 2, y: vis.midY + 140)
    }

    private func positionPanel() {
        var frame = panel.frame
        frame.size.width = width
        frame.origin = NSPoint(x: anchorTop.x, y: anchorTop.y - frame.height)
        panel.setFrame(clampedFrame(frame), display: false)
    }

    /// SwiftUI 内容高度变化时调用,保持顶边不动,带动画
    func applyHeight(_ height: CGFloat) {
        let h = max(56, height)
        guard abs(panel.frame.height - h) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = anchorTop.y - h
        frame.size.height = h
        frame.size.width = width
        frame = clampedFrame(frame)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            self?.panel.invalidateShadow()
        })
    }

    private func clampedFrame(_ input: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { NSPointInRect(anchorTop, $0.frame) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return input }
        var frame = input
        frame.origin.x = min(max(vis.minX + 8, frame.origin.x), vis.maxX - frame.width - 8)
        if frame.minY < vis.minY + 8 {
            // 下方放不下,翻到光标上方
            let topY = (caret?.maxY ?? anchorTop.y) + 10 + frame.height
            frame.origin.y = min(topY, vis.maxY - 8) - frame.height
            if frame.minY < vis.minY + 8 { frame.origin.y = vis.minY + 8 }
        }
        if frame.maxY > vis.maxY - 8 {
            frame.origin.y = vis.maxY - 8 - frame.height
        }
        return frame
    }
}

/// 翻译浮窗:⏎ 替换 / esc 取消 / ⇥ 换语言 / ⌘C 复制
@MainActor
final class PanelController: GlassPanelController {
    let model = PanelViewModel()
    var onCommit: ((String, GrabContext) -> Void)?

    private var hintTimer: Timer?
    private var committing = false

    init() {
        super.init(width: 380)
        attach(rootView: PanelRootView(model: model, onHeightChange: { [weak self] height in
            DispatchQueue.main.async { self?.applyHeight(height) }
        }))
    }

    func show(context: GrabContext) {
        hintTimer?.invalidate()
        hintTimer = nil
        moveTo(caret: context.caretRect)
        present(makeKey: true)
        model.begin(with: context)
    }

    func showHint(_ message: String) {
        hintTimer?.invalidate()
        model.showHint(message)
        moveTo(caret: nil)
        present(makeKey: false)
        hintTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    override func didHide() {
        hintTimer?.invalidate()
        hintTimer = nil
        let context = model.context
        model.reset()
        // 取消时:抓取阶段做过 ⌘A 的话,把全选收起到末尾,防止用户接着打字覆盖原文
        if !committing, let context, context.autoSelectedAll {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                KeyPoster.post(KeyPoster.keyRight)
            }
        }
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: // return / enter
            handleCommit()
            return true
        case 53: // esc
            hide()
            return true
        case 48: // tab
            model.cycleTarget()
            return true
        case 8 where event.modifierFlags.contains(.command): // ⌘C
            model.copyTranslation()
            return true
        default:
            return false
        }
    }

    private func handleCommit() {
        guard let text = model.translatedText, let context = model.context else { return }
        model.rememberCurrentTarget()
        committing = true
        hide()
        committing = false
        onCommit?(text, context)
    }
}
