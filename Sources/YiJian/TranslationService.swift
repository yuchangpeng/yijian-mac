import Foundation
import Translation

enum TranslateError: LocalizedError {
    case notInstalled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "语言包未安装"
        case .failed(let message): return message
        }
    }
}

/// 翻译引擎抽象,为以后接 LLM(润色/语气)留口子
protocol TranslationEngine {
    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String
}

/// Apple Translation 本地引擎(macOS 26+ 可直接实例化 session,离线、免费)
final class AppleTranslationEngine: TranslationEngine {
    private var sessions: [String: TranslationSession] = [:]

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        let key = "\(source.maximalIdentifier)->\(target.maximalIdentifier)"
        let session: TranslationSession
        if let cached = sessions[key] {
            session = cached
        } else {
            session = TranslationSession(installedSource: source, target: target)
            sessions[key] = session
        }

        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            sessions[key] = nil
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: Error) -> TranslateError {
        if error is TranslationError {
            let description = String(describing: error).lowercased()
            if description.contains("notinstalled") || description.contains("unsupported") {
                return .notInstalled
            }
        }
        return .failed(error.localizedDescription)
    }
}
