import Foundation
import NaturalLanguage
import Translation

enum Languages {
    /// 设置里可选的常用语言(标识符);实际支持性以系统翻译框架为准
    static let common: [String] = [
        "en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "it", "pt-BR",
        "ru", "ar", "nl", "hi", "id", "pl", "th", "tr", "uk", "vi",
    ]

    /// 浮窗下拉菜单可选的全部目标语言
    static var selectableTargets: [Locale.Language] {
        common.map { Locale.Language(identifier: $0) }
    }

    /// 启动时预热一次框架(触发 daemon 连接,并顺便打日志确认支持列表)
    static func warmUp() {
        Task.detached(priority: .utility) {
            let langs = await LanguageAvailability().supportedLanguages
            Log.translate.info("system translation supports \(langs.count) languages")
        }
    }

    static func label(for lang: Locale.Language) -> String {
        let id = normalizedIdentifier(of: lang)
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    static func label(forIdentifier id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    /// 归一化标识:非中文只保留语言码(避免出现"英语(拉丁文)"这类标签),中文按脚本区分简繁
    static func normalizedIdentifier(of lang: Locale.Language) -> String {
        guard let code = lang.languageCode?.identifier else { return lang.minimalIdentifier }
        if code == "zh" {
            return lang.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        return code
    }

    /// 语言层面的等同(zh 额外比脚本,区分简繁;忽略地区差异)
    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        guard let codeA = a.languageCode?.identifier, let codeB = b.languageCode?.identifier else { return false }
        guard codeA == codeB else { return false }
        if codeA == "zh" {
            return (a.script?.identifier ?? "Hans") == (b.script?.identifier ?? "Hans")
        }
        return true
    }

    /// 检测源语言;文本太短或识别失败按母语处理
    static func detectSource(of text: String, fallback: Locale.Language) -> Locale.Language {
        let sample = String(text.prefix(500))
        guard sample.count >= 2 else { return fallback }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage else { return fallback }
        return Locale.Language(identifier: dominant.rawValue)
    }
}

