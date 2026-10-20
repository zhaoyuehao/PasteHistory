import AppKit
import SwiftUI

// MARK: - 规格

private enum Spec {
    static let windowWidth: CGFloat = 520
    static let windowHeight: CGFloat = 540

    static let searchHeight: CGFloat = 52
    static let searchPadding: CGFloat = 18

    static let listPadding: CGFloat = 8
    static let rowSpacing: CGFloat = 2

    static let rowPadding: CGFloat = 12
    static let rowPaddingOpen: CGFloat = 13
    static let thumb: CGFloat = 34
    static let thumbOpen: CGFloat = 44

    static let corner: CGFloat = 8
    static let imageCorner: CGFloat = 10
    static let badgeCorner: CGFloat = 5

    static let imageDetail: CGFloat = 240
    static let textDetail: CGFloat = 200
    static let ocrLine: CGFloat = 26
    static let fileLine: CGFloat = 32
    static let maxFileLines: Int = 4

    // 配色：一切「块」都用 primary 的透明度表达，不用 controlBackgroundColor
    // （后者在深色下是一块脏浅灰，跟窗口底色打架）
    static let selectFill: Double = 0.24   // 深色底上 8% 等于没选中，必须够重
    static let hoverFill: Double = 0.06
    static let chipFill: Double = 0.09     // 角标 / 缩略图占位
}

private enum Motion {
    /// 就地展开 / 收起
    static let expand = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// 选中态与跟随滚动
    static let selection = Animation.easeOut(duration: 0.20)
    /// 悬停：比选中快一档，不然手感发木
    static let hover = Animation.easeOut(duration: 0.12)
    /// 连按判定：间隔小于这个值就不做动画，否则动画会堆积成迟滞
    static let repeatThreshold: TimeInterval = 0.2
}

// MARK: - 展开大图：后台解码，避免展开动画首帧空白

@MainActor
private final class ExpandedImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private var wantedID: UUID?

    func load(for item: ClipItem?) {
        guard let item, item.kind == .image || item.firstImageFilePath != nil else {
            wantedID = nil
            image = nil
            return
        }
        wantedID = item.id

        // 缓存命中：同步给出，首帧不空
        let name = item.imageFile
        let path = item.firstImageFilePath
        if let hit = ClipStore.shared.peek(named: name) ?? ClipStore.shared.peekFile(path: path) {
            image = hit
            return
        }

        image = nil
        let id = item.id
        DispatchQueue.global(qos: .userInitiated).async {
            let decoded = ClipStore.decodeImage(named: name) ?? ClipStore.decodeImage(atPath: path)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantedID == id, let decoded else { return }
                ClipStore.shared.cache(decoded, named: name, path: path)
                self.image = decoded
            }
        }
    }
}

// MARK: - 面板

struct HistoryView: View {
    @ObservedObject var store: ClipStore
    @StateObject private var loader = ExpandedImageLoader()
    @State private var selection = 0
    @State private var lastMoveAt = Date.distantPast
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
            hairline
            content
        }
        .frame(width: Spec.windowWidth, height: Spec.windowHeight)
        // 内容顶到窗口上缘，别让标题栏白白占 28pt
        .ignoresSafeArea()
        // 头部块：比内容区亮一档。层次靠材质差异，不靠多画几条线
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
            loader.load(for: current)
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
        .onChange(of: safeSelection) { _, _ in loader.load(for: current) }
    }

    private var current: ClipItem? {
        guard safeSelection < results.count else { return nil }
        return results[safeSelection]
    }

    /// 连按时不带动画：长按方向键时 0.30s 的弹簧会堆积成迟滞，速度必须让位
    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let now = Date()
        let fast = now.timeIntervalSince(lastMoveAt) < Motion.repeatThreshold
        lastMoveAt = now
        let next = min(max(safeSelection + delta, 0), results.count - 1)
        if fast {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selection = next }
        } else {
            withAnimation(Motion.selection) { selection = next }
        }
    }

    // MARK: - 搜索

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(searchFocused ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
            TextField("搜索", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清空")
            }
        }
        .padding(.horizontal, Spec.searchPadding)
        .padding(.top, 10)   // ignoresSafeArea 顶掉标题栏后，搜索区需要一点呼吸
        .frame(height: Spec.searchHeight + 10)
    }

    /// 全界面唯一一条线
    private var hairline: some View {
        Rectangle()
            .fill(searchFocused ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.6))
            .frame(height: 0.5)
    }

    // MARK: - 列表

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spec.rowSpacing, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(Array(section.items.enumerated()), id: \.element.0.id) { _, pair in
                                RowView(item: pair.0,
                                        index: pair.1,
                                        query: store.query,
                                        selected: pair.1 == safeSelection,
                                        expandedImage: pair.1 == safeSelection ? loader.image : nil)
                                    .id(pair.0.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { onPaste(pair.0) }
                                    .simultaneousGesture(TapGesture(count: 1).onEnded { selection = pair.1 })
                                    .onAppear {
                                        if pair.1 >= results.count - 8 { store.loadMore() }
                                    }
                            }
                        } header: {
                            SectionHeader(title: section.title)
                        }
                    }
                }
                .padding(Spec.listPadding)
            }
            .onChange(of: safeSelection) { _, newValue in
                guard newValue < results.count else { return }
                // 不带 anchor：只滚最小位移。anchor: .center 每按一次都把行拉到正中，
                // 整片列表跟着滑——那是「抖」的根源
                if Date().timeIntervalSince(lastMoveAt) < Motion.repeatThreshold {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(results[newValue].id) }
                } else {
                    withAnimation(Motion.selection) { proxy.scrollTo(results[newValue].id) }
                }
            }
            .onChange(of: store.query) { _, _ in selection = 0 }
        }
        // 内容区比头部暗一档，两个材质一明一暗，区域自然分开
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .center) {
            if results.isEmpty { emptyState }
        }
    }

    /// 区域划分靠分组，不靠分割线：置顶 / 今天 / 昨天 / 更早
    /// （分页与键盘导航仍按展平的 results 走，这里只影响渲染顺序）
    private var sections: [(title: String, items: [(ClipItem, Int)])] {
        var out: [(String, [(ClipItem, Int)])] = []

        var pinned: [(ClipItem, Int)] = []
        var rest: [(ClipItem, Int)] = []
        for (i, item) in results.enumerated() {
            if item.pinned { pinned.append((item, i)) } else { rest.append((item, i)) }
        }
        if !pinned.isEmpty { out.append(("置顶", pinned)) }

        var current: String?
        var bucket: [(ClipItem, Int)] = []
        for pair in rest {
            let title = Self.dayTitle(pair.0.createdAt)
            if title != current {
                if let current, !bucket.isEmpty { out.append((current, bucket)); bucket = [] }
                current = title
            }
            bucket.append(pair)
        }
        if let current, !bucket.isEmpty { out.append((current, bucket)) }
        return out
    }

    private static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return "更早"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(store.totalCount == 0 ? "你的剪贴板还没有记忆。" : "没找到。")
                .font(.system(size: 15, weight: .medium))
            Text(store.totalCount == 0 ? "⌘C 复制点什么，⇧⌘C 回来" : "换个词试试")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}

// MARK: - 分组标题

private struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, Spec.listPadding + 6)
        .padding(.vertical, 7)
        // sticky header 必须不透明，否则滚过去时文字会压在行上
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 单行

struct RowView: View {
    let item: ClipItem
    let index: Int
    let query: String
    let selected: Bool
    let expandedImage: NSImage?

    @State private var hovered = false

    private var thumbSize: CGFloat { selected ? Spec.thumbOpen : Spec.thumb }
    private var padding: CGFloat { selected ? Spec.rowPaddingOpen : Spec.rowPadding }

    var body: some View {
        VStack(spacing: 0) {
            header
            detail
                // 高度是连续量而不是结构变化：内容常驻，收起时高度归零并裁掉。
                // 用 if 插入/移除会走 appear/disappear 路径，macOS 上表现为瞬变。
                // 用 maxHeight 而不是 height：短内容不撑出一片空白
                .frame(maxHeight: selected ? detailHeight : 0)
                .clipped()
                .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, padding)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Spec.corner)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
        .animation(Motion.expand, value: selected)
    }

    /// 选中 > 悬停 > 无。悬停是「这里可以按」的承诺，必须看得见但压得住
    private var fill: Color {
        if selected { return Color.accentColor.opacity(Spec.selectFill) }
        if hovered { return Color.primary.opacity(Spec.hoverFill) }
        return Color.clear
    }

    // MARK: 头部（收起时就是整行）

    private var header: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: thumbSize, height: thumbSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(selected ? .secondary : .tertiary)
                    }
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 11))
                            .foregroundStyle(selected ? .secondary : .tertiary)
                            .lineLimit(1)
                    }
                    Text(RelativeTime.string(from: item.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? .secondary : .tertiary)
                }
            }

            Spacer(minLength: 8)
            quickBadge
        }
        .frame(height: thumbSize)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb = item.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Spec.corner)
                    .fill(Color.primary.opacity(Spec.chipFill))
                Image(systemName: symbol)
                    .font(.system(size: thumbSize * 0.45))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch item.kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    /// ⌘1–9 快速粘贴角标：可见的承诺，值得常驻
    @ViewBuilder
    private var quickBadge: some View {
        if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(selected ? .primary : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Spec.badgeCorner)
                        .fill(Color.primary.opacity(selected ? 0.14 : Spec.chipFill))
                )
        }
    }

    // MARK: 展开内容

    private var detailHeight: CGFloat {
        switch item.kind {
        case .text: return Spec.textDetail
        case .image: return Spec.imageDetail + (hasOCR ? Spec.ocrLine : 0)
        case .files: return CGFloat(min(paths.count, Spec.maxFileLines)) * Spec.fileLine + 6
        }
    }

    private var paths: [String] { item.filePaths ?? [] }
    private var hasOCR: Bool { !(item.ocrText ?? "").isEmpty }

    @ViewBuilder
    private var detail: some View {
        switch item.kind {
        case .text: textDetail
        case .image: imageDetail
        case .files: filesDetail
        }
    }

    private var textDetail: some View {
        ScrollView {
            Text(item.text ?? "")
                .font(.system(size: 13))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
        // 不固定高度：内容短则矮，上限 200 由外层 detailHeight 控制
    }

    private var imageDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let expandedImage {
                    Image(nsImage: expandedImage).resizable().scaledToFit()
                } else if let thumb = item.thumbnail {
                    // 原图还没解码完，先用缩略图顶住第一帧
                    Image(nsImage: thumb).resizable().scaledToFit()
                } else {
                    Rectangle().fill(Color.primary.opacity(Spec.chipFill))
                }
            }
            .frame(height: Spec.imageDetail)
            .clipShape(RoundedRectangle(cornerRadius: Spec.imageCorner))
            .padding(.top, 10)

            if hasOCR {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("图内文字")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(item.ocrText ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 9)
            }
        }
    }

    private var filesDetail: some View {
        VStack(spacing: 6) {
            ForEach(Array(paths.prefix(Spec.maxFileLines).enumerated()), id: \.offset) { _, path in
                FileLine(path: path)
            }
            if paths.count > Spec.maxFileLines {
                Text("还有 \(paths.count - Spec.maxFileLines) 个")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 10)
    }

    /// 摘要里高亮搜索命中
    private var summary: AttributedString {
        var attr = AttributedString(item.summary)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attr }
        var searchRange = attr.startIndex..<attr.endIndex
        while let r = attr[searchRange].range(of: q, options: .caseInsensitive) {
            attr[r].backgroundColor = Color.accentColor.opacity(0.35)
            searchRange = r.upperBound..<attr.endIndex
            if searchRange.isEmpty { break }
        }
        return attr
    }
}

// MARK: - 文件行

private struct FileLine: View {
    let path: String

    private var exists: Bool { FileManager.default.fileExists(atPath: path) }
    private var name: String { (path as NSString).lastPathComponent }

    private var size: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: n.int64Value, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(exists ? 1 : 0.4)
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let size {
                Text(size)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            if !exists {
                Text("原文件已不存在")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .frame(height: 24)
    }
}
