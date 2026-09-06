import AppKit
import ApplicationServices
import os

enum Log {
    static let app = Logger(subsystem: "dev.chendi.yijian", category: "app")
    static let grab = Logger(subsystem: "dev.chendi.yijian", category: "grab")
    static let translate = Logger(subsystem: "dev.chendi.yijian", category: "translate")
    static let paste = Logger(subsystem: "dev.chendi.yijian", category: "paste")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let coordinator = TranslateCoordinator()
    private var settingsController: SettingsWindowController?

    private let permissionItem = NSMenuItem()
    private let revertItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        HotKeyManager.shared.register(id: 1, keyCode: HotKeyManager.keyT, modifiers: HotKeyManager.optionCommand) { [weak self] in
            self?.coordinator.toggle()
        }
        HotKeyManager.shared.register(id: 2, keyCode: HotKeyManager.keyV, modifiers: HotKeyManager.optionCommand) { [weak self] in
            self?.coordinator.toggleClipboard()
        }
        ClipboardStore.shared.start()
        Languages.warmUp()
        Log.app.info("译键 launched, AX trusted=\(AXIsProcessTrusted())")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "译键")
                ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "译键")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "译键 — ⌥⌘T 翻译当前输入"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let translateItem = NSMenuItem(title: "翻译当前输入", action: #selector(triggerTranslate), keyEquivalent: "t")
        translateItem.keyEquivalentModifierMask = [.command, .option]
        translateItem.target = self
        menu.addItem(translateItem)

        let clipboardItem = NSMenuItem(title: "剪贴板历史", action: #selector(triggerClipboard), keyEquivalent: "v")
        clipboardItem.keyEquivalentModifierMask = [.command, .option]
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        revertItem.title = "还原上次替换"
        revertItem.action = #selector(revertLast)
        revertItem.target = self
        menu.addItem(revertItem)
        menu.addItem(.separator())

        permissionItem.title = "辅助功能权限:检查中…"
        permissionItem.action = #selector(openAccessibilitySettings)
        permissionItem.target = self
        menu.addItem(permissionItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出译键", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        permissionItem.title = trusted ? "辅助功能权限:已授予 ✓" : "辅助功能权限:未授予(点击去设置)"
        revertItem.isEnabled = coordinator.canRevert
    }

    @objc private func triggerTranslate() { coordinator.toggle() }
    @objc private func triggerClipboard() { coordinator.toggleClipboard() }
    @objc private func revertLast() { coordinator.revertLast() }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.show()
    }
}

// MARK: - 主流程协调

@MainActor
final class TranslateCoordinator {
    private let panelController = PanelController()
    private let clipboardPanel = ClipboardPanelController()
    private var lastReplacement: ReplacementRecord?
    private var replacing = false

    var canRevert: Bool { lastReplacement != nil }

    init() {
        panelController.onCommit = { [weak self] text, context in
            self?.performReplace(text: text, context: context)
        }
        clipboardPanel.onPaste = { item, app in
            Task { @MainActor in
                await Paster.pasteHistoryItem(item.text, into: app)
            }
        }
        clipboardPanel.onTranslate = { [weak self] item, app in
            // 从历史条目直接进入翻译浮窗;确认后译文插入当前光标处
            let context = GrabContext(text: item.text, mode: .selection, source: .clipboard,
                                      app: app, axElement: nil, selectedRange: nil, caretRect: nil,
                                      autoSelectedAll: false)
            self?.panelController.show(context: context)
        }
    }

    func toggleClipboard() {
        if clipboardPanel.isVisible {
            clipboardPanel.hide()
            return
        }
        panelController.hide()
        clipboardPanel.show()
    }

    func toggle() {
        if panelController.isVisible {
            panelController.hide()
            return
        }
        clipboardPanel.hide()
        guard !replacing else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            panelController.showHint("需要辅助功能权限:请在 系统设置 → 隐私与安全性 → 辅助功能 勾选「译键」")
            return
        }

        Task { @MainActor in
            let outcome = await TextGrabber.grab()
            switch outcome {
            case .ok(let context):
                panelController.show(context: context)
            case .fail(let message):
                panelController.showHint(message)
            }
        }
    }

    private func performReplace(text: String, context: GrabContext) {
        replacing = true
        Task { @MainActor in
            await Paster.replace(with: text, context: context)
            lastReplacement = ReplacementRecord(originalText: context.text, translatedText: text, context: context)
            replacing = false
        }
    }

    func revertLast() {
        guard let record = lastReplacement, !replacing else { return }
        replacing = true
        Task { @MainActor in
            let pasted = await Paster.revert(record)
            if !pasted {
                panelController.showHint("无法自动还原:原文已放入剪贴板,请手动粘贴")
            }
            lastReplacement = nil
            replacing = false
        }
    }
}
