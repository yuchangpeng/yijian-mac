import AppKit
import Foundation

@MainActor
final class PanelViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case hint(String)
        case translating
        case done(String)
        case needsDownload(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var sourceText: String = ""
    @Published private(set) var sourceLabel: String = ""
    @Published private(set) var targetLabel: String = ""
    @Published var copied = false

    private(set) var context: GrabContext?

    private let engine: TranslationEngine = AppleTranslationEngine()
    private var source: Locale.Language = SettingsStore.native
    private var cycle: [Locale.Language] = []
    private var index = 0
    private var requestID = 0

    var translatedText: String? {
        if case .done(let text) = state { return text }
        return nil
    }

    var currentTarget: Locale.Language? {
        index < cycle.count ? cycle[index] : nil
    }

    var availableTargets: [Locale.Language] {
        Languages.selectableTargets
    }

    /// 从下拉菜单直接选目标语言:置于循环首位并立即重译
    func selectTarget(_ lang: Locale.Language) {
        var newCycle = [lang]
        for candidate in cycle where !Languages.sameLanguage(candidate, lang) {
            newCycle.append(candidate)
        }
        cycle = newCycle
        index = 0
        translateCurrent()
    }

    func begin(with context: GrabContext) {
        self.context = context
        sourceText = context.text
        copied = false

        let native = SettingsStore.native
        let targets = SettingsStore.targets
        let detected = Languages.detectSource(of: context.text, fallback: native)
        source = detected

        // 目标优先级:上次用过的语言 → 设置的目标语 → 母语;去重、去掉与源语言相同的项
        var candidates: [Locale.Language] = []
        if let last = SettingsStore.lastTarget { candidates.append(last) }
        candidates.append(contentsOf: targets)
        candidates.append(native)
        candidates.append(Locale.Language(identifier: "en"))

        var list: [Locale.Language] = []
        for candidate in candidates {
            if !Languages.sameLanguage(detected, candidate),
               !list.contains(where: { Languages.sameLanguage($0, candidate) }) {
                list.append(candidate)
            }
        }
        if list.isEmpty { list = [native] }
        cycle = list
        index = 0
        translateCurrent()
    }

    func cycleTarget() {
        guard cycle.count > 1 else { return }
        index = (index + 1) % cycle.count
        translateCurrent()
    }

    func showHint(_ message: String) {
        context = nil
        state = .hint(message)
    }

    func reset() {
        requestID += 1
        state = .idle
        context = nil
        copied = false
    }

    func copyTranslation() {
        guard let text = translatedText else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copied = true
        rememberCurrentTarget()
    }

    /// 记住实际被使用的目标语言(替换或复制时调用)
    func rememberCurrentTarget() {
        guard let target = currentTarget else { return }
        SettingsStore.lastTargetIdentifier = Languages.normalizedIdentifier(of: target)
    }

    private func translateCurrent() {
        guard index < cycle.count else { return }
        let target = cycle[index]
        sourceLabel = Languages.label(for: source)
        targetLabel = Languages.label(for: target)
        state = .translating
        copied = false
        requestID += 1
        let id = requestID
        let text = sourceText
        let src = source

        Task {
            do {
                let output = try await engine.translate(text, from: src, to: target)
                guard id == self.requestID else { return }
                self.state = .done(output)
            } catch let error as TranslateError {
                guard id == self.requestID else { return }
                switch error {
                case .notInstalled:
                    self.state = .needsDownload("「\(Languages.label(for: target))」语言包未安装")
                case .failed(let message):
                    self.state = .error(message)
                }
            } catch {
                guard id == self.requestID else { return }
                self.state = .error(error.localizedDescription)
            }
        }
    }
}
