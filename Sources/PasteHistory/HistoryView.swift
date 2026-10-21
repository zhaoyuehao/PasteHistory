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
    /// 一块「文字块」的高度上限：标签 + 最多三行 + 间距
    static let noteBlock: CGFloat = 88
    static let noteScroll: CGFloat = 72
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
    @StateObject private var model: HistoryViewModel
    @StateObject private var loader = ExpandedImageLoader()
    @FocusState private var searchFocused: Bool

    var onPaste: (ClipItem) -> Void
    var onCopyOnly: (ClipItem) -> Void
    var onClose: () -> Void

    init(store: ClipStore,
         onPaste: @escaping (ClipItem) -> Void,
         onCopyOnly: @escaping (ClipItem) -> Void,
         onClose: @escaping () -> Void) {
        self.store = store
        _model = StateObject(wrappedValue: HistoryViewModel(store: store))
        self.onPaste = onPaste
        self.onCopyOnly = onCopyOnly
        self.onClose = onClose
    }

    private var results: [ClipItem] { model.results }
    private var safeSelection: Int { model.safeSelection }

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
            loader.load(for: model.expanded ? current : nil)
            model.rebuildSections()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phMoveDown)) { _ in model.move(1) }
        .onReceive(NotificationCenter.default.publisher(for: .phMoveUp)) { _ in model.move(-1) }
        .onReceive(NotificationCenter.default.publisher(for: .phConfirm)) { _ in
            guard let item = current else { return }
            onPaste(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phCopyOnly)) { _ in
            guard let item = current else { return }
            onCopyOnly(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phToggleExpand)) { _ in model.toggleExpanded() }
        .onReceive(NotificationCenter.default.publisher(for: .phDelete)) { _ in
            guard current != nil else { return }
            model.deleteCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phPin)) { _ in
            guard current != nil else { return }
            model.togglePinCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phClose)) { _ in onClose() }
        // 每次打开面板都是一次新的「找」：回到第一条并收起，一屏能扫到十条
        .onReceive(NotificationCenter.default.publisher(for: .phPanelWillShow)) { _ in model.resetForPresentation() }
        .onReceive(NotificationCenter.default.publisher(for: .phQuickPaste)) { note in
            guard let index = note.object as? Int, index < results.count else { return }
            onPaste(results[index])
        }
        .onChange(of: safeSelection) { _, _ in loader.load(for: model.expanded ? current : nil) }
        // 收起时不解码大图：一屏十条时没人看得见，白费一次后台解码
        .onChange(of: model.expanded) { _, isOn in loader.load(for: isOn ? current : nil) }
        .onChange(of: store.displayed) { _, _ in model.rebuildSections() }
    }

    private var current: ClipItem? { model.current }

    // MARK: - 搜索

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Icon.action))
                // 聚焦时点亮，未聚焦时也不该淡到看不见——图标是位置的承诺
                .foregroundStyle(searchFocused ? Color.accentColor : Palette.meta)
            TextField(L10n.search, text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: Scale.field))
                .focused($searchFocused)
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Icon.action))
                        .foregroundStyle(Palette.meta)
                }
                .buttonStyle(.plain)
                .help(L10n.clear)
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
                                        expanded: pair.1 == safeSelection && model.expanded,
                                        expandedImage: pair.1 == safeSelection && model.expanded ? loader.image : nil,
                                        onPin: { model.togglePin(at: pair.1) },
                                        onDelete: { model.delete(at: pair.1) })
                                    .id(pair.0.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { onPaste(pair.0) }
                                    // 鼠标也要能展开：点已选中的那一行就是切换展开
                                    .simultaneousGesture(TapGesture(count: 1).onEnded {
                                        if pair.1 == safeSelection {
                                            model.toggleExpanded()
                                        } else {
                                            model.select(pair.1)
                                        }
                                    })
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
                if Date().timeIntervalSince(model.lastMoveAt) < Motion.repeatThreshold {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(results[newValue].id) }
                } else {
                    withAnimation(Motion.selection) { proxy.scrollTo(results[newValue].id) }
                }
            }
            .onChange(of: store.query) { _, _ in model.resetSelection() }
        }
        // 内容区比头部暗一档，两个材质一明一暗，区域自然分开
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .center) {
            if results.isEmpty { emptyState }
        }
    }

    /// 区域划分靠分组，不靠分割线：置顶 / 今天 / 昨天 / 更早
    /// （分页与键盘导航仍按展平的 results 走，这里只影响渲染顺序）
    private var sections: [HistorySection] { model.sections }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(store.totalCount == 0 ? L10n.noHistory : L10n.noMatch)
                .font(.system(size: Scale.field, weight: .medium))
            Text(store.totalCount == 0 ? L10n.copySomething : L10n.tryAnother)
                .font(.system(size: Scale.body))
                .foregroundStyle(Palette.meta)
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
                .font(.system(size: Scale.meta, weight: .medium))
                .foregroundStyle(Palette.meta)
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
    /// 收起是默认态；只有 expanded 才放大缩略图、加宽内边距、长出内容区
    let expanded: Bool
    let expandedImage: NSImage?
    var onPin: () -> Void
    var onDelete: () -> Void

    @State private var hovered = false

    /// 缩略图与内边距跟展开走，不跟选中走：
    /// 选中的行如果也撑大，收起状态下一样扫不了几条
    private var thumbSize: CGFloat { expanded ? Spec.thumbOpen : Spec.thumb }
    private var padding: CGFloat { expanded ? Spec.rowPaddingOpen : Spec.rowPadding }

    var body: some View {
        VStack(spacing: 0) {
            header
            detail
                // 高度是连续量而不是结构变化：内容常驻，收起时高度归零并裁掉。
                // 用 if 插入/移除会走 appear/disappear 路径，macOS 上表现为瞬变。
                // 用 maxHeight 而不是 height：短内容不撑出一片空白
                .frame(maxHeight: expanded ? detailHeight : 0)
                .clipped()
                .opacity(expanded ? 1 : 0)
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
        .animation(Motion.expand, value: expanded)
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
                    .font(.system(size: Scale.body))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: Icon.mark))
                            .foregroundStyle(Palette.meta)
                    }
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: Scale.meta))
                            .foregroundStyle(Palette.meta)
                            .lineLimit(1)
                    }
                    Text(RelativeTime.string(from: item.createdAt))
                        .font(.system(size: Scale.meta))
                        .foregroundStyle(Palette.meta)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .frame(height: thumbSize)
    }

    /// 右侧固定 44 宽：常态是 ⌘N 角标，悬停时原位换成置顶 / 删除。
    /// 宽度恒定，所以悬停不会把摘要挤动；也终于让鼠标能操作单条
    private var trailing: some View {
        ZStack {
            quickBadge
                .opacity(hovered ? 0 : 1)
            HStack(spacing: 4) {
                RowActionButton(symbol: "pin.fill", label: L10n.pinItem, action: onPin)
                RowActionButton(symbol: "trash", label: L10n.deleteItem, action: onDelete)
            }
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
        .frame(minWidth: 44, alignment: .trailing)
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
                    .font(.system(size: expanded ? Icon.thumbOpen : Icon.thumb))
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

    /// ⌘1–9 快速粘贴角标：可见的承诺，值得常驻。
    /// 常驻的前提是读得清——tertiaryLabelColor 在浅色下只有 1.73:1，等于没写
    @ViewBuilder
    private var quickBadge: some View {
        if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: Scale.meta, design: .monospaced))
                .foregroundStyle(selected ? .primary : Palette.meta)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Spec.badgeCorner)
                        .fill(Color.primary.opacity(selected ? 0.14 : Spec.chipFill))
                )
                // 图标化不能牺牲读屏：⌘1 念出来没人听得懂
                .accessibilityLabel(L10n.quickPaste(index + 1))
        }
    }

    // MARK: 展开内容

    private var detailHeight: CGFloat {
        switch item.kind {
        case .text: return Spec.textDetail
        case .image:
            return Spec.imageDetail
                + (hasText ? Spec.noteBlock : 0)
                + (hasOCR ? Spec.noteBlock : 0)
        case .files: return CGFloat(min(paths.count, Spec.maxFileLines)) * Spec.fileLine + 6
        }
    }

    private var paths: [String] { item.filePaths ?? [] }
    private var hasOCR: Bool { !(item.ocrText ?? "").isEmpty }
    private var hasText: Bool { !(item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
                .font(.system(size: Scale.body))
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

            // 图片自带的文字、OCR 出来的文字，都是内容——内容必须能选中、能复制。
            // 乔布斯删的是「解释软件的 UI」，不是用户要拿走的东西
            if hasText {
                NoteBlock(label: L10n.attachedText, content: item.text ?? "")
            }
            if hasOCR {
                NoteBlock(label: L10n.imageText, content: item.ocrText ?? "")
            }
        }
    }

    private var filesDetail: some View {
        VStack(spacing: 6) {
            ForEach(Array(paths.prefix(Spec.maxFileLines).enumerated()), id: \.offset) { _, path in
                FileLine(path: path)
            }
            if paths.count > Spec.maxFileLines {
                Text(L10n.moreFiles(paths.count - Spec.maxFileLines))
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.meta)
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

/// 行内图标按钮：20 见方，悬停才出现，必须有名字——图标化不能牺牲读屏
private struct RowActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Icon.action))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: Spec.badgeCorner)
                        .fill(Color.primary.opacity(hovering ? 0.14 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(hovering ? .primary : .secondary)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering = $0 }
    }
}

// MARK: - 文字块

/// 图片附带的文字 / OCR 出来的文字：可选中即复制，不额外给按钮
private struct NoteBlock: View {
    let label: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: Scale.meta))
                .foregroundStyle(Palette.meta)
            ScrollView {
                Text(content)
                    .font(.system(size: Scale.body))
                    // 这是要拿走的内容，不是注释：按正文对比度给
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Spec.noteScroll)
        }
        .padding(.top, 9)
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
                .font(.system(size: Scale.body))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let size {
                Text(size)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.meta)
                    .monospacedDigit()
            }
            if !exists {
                Text(L10n.fileMissing)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.warning)
            }
        }
        .frame(height: 24)
    }
}
