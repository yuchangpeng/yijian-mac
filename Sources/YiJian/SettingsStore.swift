import Foundation

/// UserDefaults 包装;键与 SettingsView 里的 @AppStorage 保持一致
enum SettingsStore {
    private static let defaults = UserDefaults.standard

    static var nativeIdentifier: String {
        defaults.string(forKey: "nativeLang") ?? "zh-Hans"
    }

    static var targetIdentifiers: [String] {
        [
            defaults.string(forKey: "target1") ?? "en",
            defaults.string(forKey: "target2") ?? "ja",
            defaults.string(forKey: "target3") ?? "ko",
        ]
    }

    static var native: Locale.Language {
        Locale.Language(identifier: nativeIdentifier)
    }

    static var targets: [Locale.Language] {
        targetIdentifiers.map { Locale.Language(identifier: $0) }
    }

    static var clipboardHistoryEnabled: Bool {
        (defaults.object(forKey: "clipboardHistoryEnabled") as? Bool) ?? true
    }

    enum PanelMaterial: String {
        case glassClear    // 液态玻璃(透明)
        case glassRegular  // 液态玻璃(标准,边缘有折射描边)
        case frosted       // 磨砂玻璃(Spotlight 风格)
    }

    static var panelMaterial: PanelMaterial {
        PanelMaterial(rawValue: defaults.string(forKey: "panelMaterial") ?? "") ?? .glassClear
    }

    /// 上次实际使用(替换/复制)的目标语言,下次优先沿用
    static var lastTargetIdentifier: String? {
        get { defaults.string(forKey: "lastTarget") }
        set { defaults.set(newValue, forKey: "lastTarget") }
    }

    static var lastTarget: Locale.Language? {
        lastTargetIdentifier.map { Locale.Language(identifier: $0) }
    }
}
