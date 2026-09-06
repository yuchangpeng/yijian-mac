import AppKit
import ServiceManagement
import SwiftUI
import Translation

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "译键 设置"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            LanguagePacksView()
                .tabItem { Label("语言包", systemImage: "arrow.down.circle") }
        }
        .frame(width: 440, height: 470)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("nativeLang") private var native = "zh-Hans"
    @AppStorage("target1") private var target1 = "en"
    @AppStorage("target2") private var target2 = "ja"
    @AppStorage("target3") private var target3 = "ko"
    @AppStorage("clipboardHistoryEnabled") private var clipboardHistoryEnabled = true
    @AppStorage("panelMaterial") private var panelMaterial = "glassClear"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("语言") {
                languagePicker("母语(外语会译回此语言)", $native)
                languagePicker("目标语言", $target1)
                languagePicker("备选一(⇥ 切换)", $target2)
                languagePicker("备选二", $target3)
            }
            Section("剪贴板历史") {
                Toggle("记录剪贴板历史", isOn: $clipboardHistoryEnabled)
                LabeledContent("快捷键", value: "⌥ ⌘ V")
                Button("清空历史") {
                    ClipboardStore.shared.clear()
                }
                .controlSize(.small)
            }
            Section("外观") {
                Picker("浮窗材质", selection: $panelMaterial) {
                    Text("液态玻璃(透明)").tag("glassClear")
                    Text("液态玻璃(标准)").tag("glassRegular")
                    Text("磨砂玻璃").tag("frosted")
                }
            }
            Section("通用") {
                LabeledContent("翻译快捷键", value: "⌥ ⌘ T")
                Toggle("开机自启", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                LabeledContent("版本", value: "0.1.0")
            } footer: {
                Text("在任何输入框输完文字,按 ⌥⌘T 预览译文,回车替换。翻译全程本地完成,不联网。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func languagePicker(_ title: String, _ selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Languages.common, id: \.self) { id in
                Text(Languages.label(forIdentifier: id)).tag(id)
            }
        }
    }
}

/// 全项目唯一使用 .translationTask 的地方:这里拿到的 session 才有权限弹系统语言包下载 UI
struct LanguagePacksView: View {
    @AppStorage("nativeLang") private var native = "zh-Hans"
    @State private var statuses: [String: LanguageAvailability.Status] = [:]
    @State private var downloadConfig: TranslationSession.Configuration?

    var body: some View {
        Form {
            Section {
                ForEach(Languages.common, id: \.self) { id in
                    if id != native { row(id) }
                }
            } header: {
                Text("语言包(下载后离线翻译)")
            } footer: {
                Text("下载由系统完成;也可在 系统设置 → 通用 → 语言与地区 → 翻译语言 中管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
        .translationTask(downloadConfig) { session in
            if session.canRequestDownloads {
                try? await session.prepareTranslation()
            }
            await refresh()
        }
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        let lang = Locale.Language(identifier: id)
        HStack {
            Text(Languages.label(forIdentifier: id))
            Spacer()
            switch statuses[id] {
            case .installed:
                Label("已安装", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            case .supported:
                Button("下载") {
                    if var config = downloadConfig {
                        config.invalidate()
                        downloadConfig = config
                    }
                    downloadConfig = TranslationSession.Configuration(
                        source: Locale.Language(identifier: native),
                        target: lang
                    )
                }
                .controlSize(.small)
            case .unsupported:
                Text("不支持").font(.caption).foregroundStyle(.tertiary)
            default:
                ProgressView().controlSize(.small)
            }
        }
    }

    private func refresh() async {
        let availability = LanguageAvailability()
        let nativeLang = Locale.Language(identifier: native)
        var result: [String: LanguageAvailability.Status] = [:]
        for id in Languages.common where id != native {
            result[id] = await availability.status(from: nativeLang, to: Locale.Language(identifier: id))
        }
        statuses = result
    }
}
