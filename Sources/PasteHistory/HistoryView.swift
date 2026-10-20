import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: ClipStore
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    var onPaste: (ClipItem) -> Void
    var onCopyOnly: (ClipItem) -> Void
    var onClose: () -> Void

    private var results: [ClipItem] { store.displayed }
    private var safeSelection: Int {
        guard !results.isEmpty else { return 0 }
        return min(max(selection, 0), results.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .phMoveDown)) { _ in move(1) }
        .onReceive(NotificationCenter.default.publisher(for: .phMoveUp)) { _ in move(-1) }
        .onReceive(NotificationCenter.default.publisher(for: .phConfirm)) { _ in
            guard let item = current else { return }
            onPaste(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phCopyOnly)) { _ in
            guard let item = current else { return }
            onCopyOnly(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phDelete)) { _ in
            guard let item = current else { return }
            store.remove(id: item.id)
            selection = max(0, safeSelection - 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phPin)) { _ in
            guard let item = current else { return }
            store.togglePin(id: item.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phClose)) { _ in onClose() }
        .onReceive(NotificationCenter.default.publisher(for: .phQuickPaste)) { note in
            guard let index = note.object as? Int, index < results.count else { return }
            onPaste(results[index])
        }
    }

    private var current: ClipItem? {
        guard safeSelection < results.count else { return nil }
        return results[safeSelection]
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(safeSelection + delta, 0), results.count - 1)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索剪贴板历史（含图片内文字）…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text("\(store.matchCount) / \(store.totalCount)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 主体

    private var content: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: 320)
            Divider()
            previewPane
                .frame(maxWidth: .infinity)
        }
    }

    private var listPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        RowView(item: item, selected: index == safeSelection)
                            .id(item.id)
                            .contentShape(Rectangle())
                            // 单击只选中；双击才粘贴到系统当前聚焦的输入框
                            .onTapGesture(count: 2) { onPaste(item) }
                            .simultaneousGesture(TapGesture(count: 1).onEnded {
                                selection = index
                            })
                            .onAppear {
                                // 滚动接近底部时加载下一页
                                if index >= results.count - 8 {
                                    store.loadMore()
                                }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: safeSelection) { _, newValue in
                guard newValue < results.count else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(results[newValue].id, anchor: .center)
                }
            }
            .onChange(of: store.query) { _, _ in
                selection = 0
            }
        }
        .overlay(alignment: .center) {
            if results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: store.totalCount == 0 ? "clipboard" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(store.totalCount == 0 ? "还没有剪贴板记录" : "没有匹配的内容")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if store.totalCount == 0 {
                        Text("现在按 ⌘C 复制点什么，再按 ⇧⌘C 回来")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var previewPane: some View {
        Group {
            if let item = current {
                // .image 读 images 目录；.files 里的图片文件（微信 jpg 等）读原路径
                PreviewPane(item: item, image: store.image(named: item.imageFile)
                            ?? store.fileImage(path: item.firstImageFilePath))
            } else {
                VStack {
                    Spacer()
                    Text("未选择")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 底部提示

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "选择")
            hint("⏎ / 双击", "粘贴到输入框")
            hint("⌘C", "仅复制")
            hint("⌘1-9", "快速粘贴")
            hint("⌘P", "置顶")
            hint("⌘⌫", "删除")
            hint("esc", "关闭")
            Spacer()
            Text("⇧⌘C 随时唤起")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 单行

struct RowView: View {
    let item: ClipItem
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.summary)
                    .font(.system(size: 12.5))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Text(RelativeTime.string(from: item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.9))
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .text:
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
        case .image:
            Image(systemName: "photo")
                .foregroundStyle(.pink)
        case .files:
            Image(systemName: "folder")
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - 预览

struct PreviewPane: View {
    let item: ClipItem
    let image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(item.kind == .text ? "文本" : (item.kind == .image ? "图片" : "文件"),
                      systemImage: item.kind == .text ? "doc.text" : (item.kind == .image ? "photo" : "folder"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let app = item.sourceApp {
                    Text("来自 \(app)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Text(RelativeTime.string(from: item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                if let text = item.text {
                    Text("\(text.count) 字符 · \(max(1, text.components(separatedBy: .newlines).count)) 行")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch item.kind {
                case .text:
                    ScrollView {
                        Text(item.text ?? "")
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                case .image:
                    if let image {
                        VStack {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            // 图文记录：复制时附带的文字
                            if let text = item.text, !text.isEmpty {
                                ScrollView {
                                    Text(text)
                                        .font(.system(size: 11.5))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .frame(maxHeight: 120)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                            }
                            if let ocr = item.ocrText, !ocr.isEmpty {
                                ScrollView {
                                    Text(ocr)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .frame(maxHeight: 120)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                            }
                        }
                        .padding(12)
                    } else {
                        placeholder("图片已丢失")
                    }
                case .files:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            // 图片文件（微信 jpg 等）：显示预览图和 OCR 文本
                            if let image {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                if let ocr = item.ocrText, !ocr.isEmpty {
                                    Text(ocr)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            ForEach(item.filePaths ?? [], id: \.self) { path in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc")
                                        .foregroundStyle(.secondary)
                                    Text(path)
                                        .font(.system(size: 11.5))
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("显示") {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                    }
                                    .font(.system(size: 11))
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
