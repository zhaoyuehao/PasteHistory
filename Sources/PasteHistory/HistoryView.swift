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
            // 内嵌胶囊：聚焦前与顶栏底色接近，聚焦后才描边高亮
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(searchFocused ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
                TextField("搜索剪贴板历史（含图片内文字）…", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清空搜索")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(searchFocused ? 1 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(searchFocused ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.5),
                            lineWidth: searchFocused ? 1.5 : 1)
            )

            Picker("", selection: $store.filter) {
                ForEach(ClipFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .frame(width: 214)

            Text(store.query.isEmpty && store.filter == .all
                 ? "\(store.totalCount)"
                 : "\(store.matchCount) / \(store.totalCount)")
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
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.6))
                .frame(width: 1)
            previewPane
                .frame(maxWidth: .infinity)
        }
    }

    private var listPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        RowView(item: item, index: index, query: store.query, selected: index == safeSelection)
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
            .onChange(of: store.filter) { _, _ in
                selection = 0
            }
        }
        .overlay(alignment: .center) {
            if results.isEmpty { emptyState }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.totalCount == 0 ? "clipboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.totalCount == 0 ? "还没有剪贴板记录" : "没有匹配的内容")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if store.totalCount == 0 {
                HStack(spacing: 4) {
                    Text("按")
                    keyCap("⌘C")
                    Text("复制点什么，再按")
                    keyCap("⇧⌘C")
                    Text("回来")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            } else {
                Text("换个关键词，或切回「全部」筛选")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .multilineTextAlignment(.center)
    }

    private var previewPane: some View {
        Group {
            if let item = current {
                // .image 读 images 目录；.files 里的图片文件（微信 jpg 等）读原路径
                PreviewPane(item: item,
                            image: store.image(named: item.imageFile)
                                ?? store.fileImage(path: item.firstImageFilePath),
                            onCopy: { onCopyOnly(item) },
                            onPin: { store.togglePin(id: item.id) })
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("未选择")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 底部提示

    private var footer: some View {
        HStack(spacing: 12) {
            hint("↑↓", "选择")
            hint("⏎", "粘贴")
            hint("⌘1-9", "快速粘贴")
            hint("⌘⌫", "删除")
            hint("esc", "关闭")
            Spacer()
            Image(systemName: iCloudSync.shared.isActive ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 10))
                .foregroundStyle(iCloudSync.shared.isActive ? Color.green : Color(NSColor.tertiaryLabelColor))
            Text(iCloudSync.shared.isActive ? "iCloud 已同步" : "iCloud 未连接")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            keyCap(key)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6))
            )
    }
}

// MARK: - 单行

struct RowView: View {
    let item: ClipItem
    let index: Int
    let query: String
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary)
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

            HStack(spacing: 6) {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(NSColor.separatorColor).opacity(0.6))
                        )
                }
                quickBadge
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
    }

    /// ⌘1–9 快速粘贴角标，只对前 9 条显示（与 phQuickPaste 的实际行为一致）
    @ViewBuilder
    private var quickBadge: some View {
        if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: 10.5))
                .foregroundStyle(selected ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color(NSColor.windowBackgroundColor)
                                : Color(NSColor.controlBackgroundColor).opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(selected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
    }

    /// 摘要里高亮搜索词；无搜索词时原样返回
    private var summary: AttributedString {
        var attr = AttributedString(item.summary)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attr }
        var searchRange = attr.startIndex..<attr.endIndex
        while let r = attr[searchRange].range(of: q, options: .caseInsensitive) {
            attr[r].backgroundColor = .yellow.opacity(0.45)
            searchRange = r.upperBound..<attr.endIndex
            if searchRange.isEmpty { break }
        }
        return attr
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

/// 预览区统一的卡片底色 / 描边 / 圆角
private enum PreviewChrome {
    static var card: Color { Color(NSColor.controlBackgroundColor).opacity(0.55) }
    static var hair: Color { Color(NSColor.separatorColor).opacity(0.6) }
    static let radius: CGFloat = 10
}

/// 透明图的棋盘底：固定浅灰，不跟随主题，否则看不出哪些区域是透明的
private enum PreviewArt {
    static let checkerboard: NSImage = {
        let s: CGFloat = 8
        let image = NSImage(size: NSSize(width: s * 2, height: s * 2))
        image.lockFocus()
        NSColor(white: 0.95, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s * 2, height: s * 2).fill()
        NSColor(white: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        NSRect(x: s, y: s, width: s, height: s).fill()
        image.unlockFocus()
        return image
    }()
}

struct PreviewPane: View {
    let item: ClipItem
    let image: NSImage?
    var onCopy: () -> Void = {}
    var onPin: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreviewHeader(item: item, onCopy: onCopy, onPin: onPin)
            Rectangle()
                .fill(PreviewChrome.hair)
                .frame(height: 1)
            Group {
                switch item.kind {
                case .text:
                    TextPreview(item: item)
                case .image:
                    ImagePreview(item: item, image: image)
                case .files:
                    FilesPreview(item: item, image: image)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 预览头部

private struct PreviewHeader: View {
    let item: ClipItem
    var onCopy: () -> Void
    var onPin: () -> Void

    private var badge: (String, Color) {
        switch item.kind {
        case .text: return ("文本", Color.accentColor)
        case .image: return ("图片", Color.pink)
        case .files: return ("文件", Color.green)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(badge.0)
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badge.1.opacity(0.13))
                .foregroundStyle(badge.1)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            if let app = item.sourceApp {
                Text("来自 \(app)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(RelativeTime.string(from: item.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            if let text = item.text, !text.isEmpty {
                Text("\(text.count) 字符 · \(max(1, text.components(separatedBy: .newlines).count)) 行")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button(action: onCopy) {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .help("⌘C　仅写回剪贴板，不模拟粘贴")

            Button(action: onPin) {
                Label(item.pinned ? "已置顶" : "置顶", systemImage: item.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(item.pinned ? Color.orange : Color.primary)
            .help("⌘P")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 文本预览

private struct TextPreview: View {
    let item: ClipItem

    private var text: String { item.text ?? "" }

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "（空文本）" : text)
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
        }
        .background(
            RoundedRectangle(cornerRadius: PreviewChrome.radius)
                .fill(PreviewChrome.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PreviewChrome.radius)
                .stroke(PreviewChrome.hair)
        )
        .padding(12)
    }
}

// MARK: - 图片预览

private struct ImagePreview: View {
    let item: ClipItem
    let image: NSImage?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("图片已丢失")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Image(nsImage: PreviewArt.checkerboard)
                    .resizable(resizingMode: .tile)
            )
            .clipShape(RoundedRectangle(cornerRadius: PreviewChrome.radius))
            .overlay(
                RoundedRectangle(cornerRadius: PreviewChrome.radius)
                    .stroke(PreviewChrome.hair)
            )

            if let text = item.text, !text.isEmpty {
                NoteCard(title: "附带文字", systemImage: "text.quote", content: text)
            }
            if let ocr = item.ocrText, !ocr.isEmpty {
                NoteCard(title: "图片内文字", systemImage: "text.viewfinder", content: ocr)
            }
        }
        .padding(12)
    }
}

private struct NoteCard: View {
    let title: String
    let systemImage: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            ScrollView {
                Text(content)
                    .font(.system(size: 11.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(PreviewChrome.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PreviewChrome.hair))
    }
}

// MARK: - 文件预览

private struct FilesPreview: View {
    let item: ClipItem
    let image: NSImage?

    private var paths: [String] { item.filePaths ?? [] }

    private var totalSize: String? {
        var total: Int64 = 0
        for path in paths {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let n = attrs[.size] as? NSNumber else { continue }
            total += n.int64Value
        }
        return total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 180)
                        .background(
                            Image(nsImage: PreviewArt.checkerboard)
                                .resizable(resizingMode: .tile)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PreviewChrome.radius))
                        .overlay(
                            RoundedRectangle(cornerRadius: PreviewChrome.radius)
                                .stroke(PreviewChrome.hair)
                        )
                }

                HStack(spacing: 6) {
                    Text("\(paths.count) 个文件")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let totalSize {
                        Text("共 \(totalSize)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    Spacer()
                }

                ForEach(paths, id: \.self) { FileRow(path: $0) }
            }
            .padding(12)
        }
    }
}

private struct FileRow: View {
    let path: String

    private var exists: Bool { FileManager.default.fileExists(atPath: path) }
    private var name: String { (path as NSString).lastPathComponent }
    private var directory: String { (path as NSString).deletingLastPathComponent }

    private var size: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: n.int64Value, countStyle: .file)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 30, height: 30)
                .opacity(exists ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(directory)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !exists {
                    Text("原文件已不存在，粘贴不会成功")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let size {
                    Text(size)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .disabled(!exists)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(PreviewChrome.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PreviewChrome.hair))
    }
}
