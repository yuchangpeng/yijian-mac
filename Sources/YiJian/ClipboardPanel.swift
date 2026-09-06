import AppKit
import SwiftUI

@MainActor
final class ClipPanelModel: ObservableObject {
    @Published var selectedIndex = 0
}

/// 剪贴板历史浮窗:↑↓/数字选择,⏎ 粘贴,⇥ 翻译选中条目,⌘⌫ 删除,esc 关闭
@MainActor
final class ClipboardPanelController: GlassPanelController {
    let model = ClipPanelModel()
    var onPaste: ((ClipItem, NSRunningApplication?) -> Void)?
    var onTranslate: ((ClipItem, NSRunningApplication?) -> Void)?

    private var targetApp: NSRunningApplication?

    static let visibleLimit = 30

    init() {
        super.init(width: 400)
        attach(rootView: ClipPanelRootView(
            store: ClipboardStore.shared,
            model: model,
            onHeightChange: { [weak self] height in
                DispatchQueue.main.async { self?.applyHeight(height) }
            },
            onSelect: { [weak self] index in
                self?.pasteItem(at: index)
            }
        ))
    }

    func show() {
        targetApp = NSWorkspace.shared.frontmostApplication
        model.selectedIndex = 0
        moveTo(caret: nil)
        present(makeKey: true)
    }

    private var visibleItems: [ClipItem] {
        Array(ClipboardStore.shared.items.prefix(Self.visibleLimit))
    }

    private func pasteItem(at index: Int) {
        let items = visibleItems
        guard index >= 0, index < items.count else { return }
        let item = items[index]
        let app = targetApp
        hide()
        onPaste?(item, app)
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        let items = visibleItems
        switch event.keyCode {
        case 125: // ↓
            model.selectedIndex = min(model.selectedIndex + 1, max(0, items.count - 1))
            return true
        case 126: // ↑
            model.selectedIndex = max(model.selectedIndex - 1, 0)
            return true
        case 36, 76: // return / enter
            pasteItem(at: model.selectedIndex)
            return true
        case 53: // esc
            hide()
            return true
        case 48: // tab → 翻译选中条目
            if model.selectedIndex < items.count {
                let item = items[model.selectedIndex]
                let app = targetApp
                hide()
                onTranslate?(item, app)
            }
            return true
        case 51 where event.modifierFlags.contains(.command): // ⌘⌫ 删除
            if model.selectedIndex < items.count {
                ClipboardStore.shared.remove(id: items[model.selectedIndex].id)
                model.selectedIndex = min(model.selectedIndex, max(0, visibleItems.count - 1))
            }
            return true
        default:
            if let ch = event.charactersIgnoringModifiers, ch.count == 1,
               let n = Int(ch), (1...9).contains(n) {
                pasteItem(at: n - 1)
                return true
            }
            return false
        }
    }
}

// MARK: - 视图

struct ClipPanelRootView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var model: ClipPanelModel
    var onHeightChange: (CGFloat) -> Void
    var onSelect: (Int) -> Void

    var body: some View {
        ClipPanelView(store: store, model: model, onSelect: onSelect)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { onHeightChange($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ClipPanelView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var model: ClipPanelModel
    var onSelect: (Int) -> Void

    private var visible: [ClipItem] {
        Array(store.items.prefix(ClipboardPanelController.visibleLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("剪贴板历史")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.items.isEmpty {
                    Text("\(store.items.count) 条")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if visible.isEmpty {
                Text("还没有记录 — 先去复制点什么吧")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                                row(index: index, item: item)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(index) }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                    .frame(height: listHeight)
                    .onChange(of: model.selectedIndex) { _, index in
                        let items = visible
                        if index >= 0, index < items.count {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(items[index].id)
                            }
                        }
                    }
                }
                footer
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    private var listHeight: CGFloat {
        min(336, CGFloat(visible.count) * 56)
    }

    private func row(index: Int, item: ClipItem) -> some View {
        let selected = index == model.selectedIndex
        return HStack(alignment: .top, spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "·")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 17, height: 17)
                .background(Circle().fill(.quaternary.opacity(selected ? 0.9 : 0.45)))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(item.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let app = item.appName {
                        Text(app)
                        Text("·")
                    }
                    Text(item.date, style: .relative)
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(selected ? 0.55 : 0)))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            keyHint("⏎", "粘贴")
            keyHint("⇥", "翻译")
            keyHint("1-9", "快选")
            keyHint("⌘⌫", "删除")
            keyHint("esc", "关闭")
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
