import SwiftUI

/// 浮窗根视图:固定宽度、自然高度,把内容高度回报给 PanelController
struct PanelRootView: View {
    @ObservedObject var model: PanelViewModel
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        PanelView(model: model)
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { onHeightChange($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .idle:
                EmptyView()
            case .hint(let message):
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                header
                Divider().opacity(0.4).padding(.vertical, 9)
                content
                footer.padding(.top, 11)
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.sourceLabel)
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
            Menu {
                ForEach(model.availableTargets, id: \.maximalIdentifier) { lang in
                    Button {
                        model.selectTarget(lang)
                    } label: {
                        if let current = model.currentTarget, Languages.sameLanguage(lang, current) {
                            Label(Languages.label(for: lang), systemImage: "checkmark")
                        } else {
                            Text(Languages.label(for: lang))
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(model.targetLabel).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            Text("本地翻译")
                .font(.system(size: 9.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary.opacity(0.55)))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.sourceText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            switch model.state {
            case .translating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("翻译中…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            case .done(let text):
                Text(text)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .lineLimit(14)
                    .fixedSize(horizontal: false, vertical: true)
            case .needsDownload(let message):
                VStack(alignment: .leading, spacing: 5) {
                    Label(message, systemImage: "arrow.down.circle")
                        .font(.system(size: 13))
                    Text("打开 译键 设置 → 语言包 下载后即可离线使用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            keyHint("⏎", "替换")
            keyHint("⇥", "换语言")
            keyHint("esc", "取消")
            keyHint("⌘C", model.copied ? "已复制 ✓" : "复制")
            Spacer()
        }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4.5).fill(.quaternary.opacity(0.6)))
            Text(label).font(.system(size: 10.5))
        }
        .foregroundStyle(.secondary)
    }
}
