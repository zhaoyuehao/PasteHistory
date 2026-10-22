import AppKit
import SwiftUI

// MARK: - 规格

private enum Spec {
    static let searchHeight: CGFloat = 52
    static let searchPadding: CGFloat = Rhythm.xxl

    static let listPadding: CGFloat = 8
    static let rowSpacing: CGFloat = 2

    static let rowPadding: CGFloat = Rhythm.xl
    static let thumb: CGFloat = 34

    // 8:5 = Fibonacci φ 对（「黄金圆」的整数近似）
    static let corner: CGFloat = 8
    static let badgeCorner: CGFloat = 5

    /// 撞到顶/底时整片内容被推出去的距离（列表与预览大窗共用，单一来源在 Motion）
    static let bounceDistance = Motion.bounceDistance

    // 配色：一切「块」都用 primary 的透明度表达，不用 controlBackgroundColor
    // （后者在深色下是一块脏浅灰，跟窗口底色打架）
    static let selectFill: Double = 0.24   // 深色底上 8% 等于没选中，必须够重
    static let hoverFill: Double = 0.06
    static let chipFill: Double = 0.09     // 角标 / 缩略图占位
}

/// 选中高亮的共享 id：matchedGeometryEffect 靠它把矩形从上一行的位置补间到这一行
private enum Highlight {
    static let id = "selectionHighlight"
}

/// 扁平列表条目：分组标题或剪贴记录，id 全局稳定
private enum ListEntry: Identifiable {
    case header(String)
    case item(ClipItem, Int)

    var id: String {
        switch self {
        case .header(let title): return "header:" + title
        case .item(let item, _): return item.id.uuidString
        }
    }
}

// MARK: - 面板

struct HistoryView: View {
    @ObservedObject var store: ClipStore
    /// 由 PanelController 持有并传入：预览大窗要跟着选中条目联动，
    /// 共享同一个 ViewModel 比通知转发少一层状态
    @ObservedObject private var model: HistoryViewModel
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionSpace
    /// 边界橡皮筋：撞到顶/底时整片内容纵向下沉一下再弹回
    @State private var bounce: CGFloat = 0

    var onPaste: (ClipItem) -> Void
    var onCopyOnly: (ClipItem) -> Void
    var onClose: () -> Void

    init(store: ClipStore,
         model: HistoryViewModel,
         onPaste: @escaping (ClipItem) -> Void,
         onCopyOnly: @escaping (ClipItem) -> Void,
         onClose: @escaping () -> Void) {
        self.store = store
        self.model = model
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
        // 高度不写死：贴着输入框放不下时窗口会收，列表跟着滚。
        // 写死 647 的话，窗口被压小后 SwiftUI 会把内容裁掉而不是滚动
        .frame(minWidth: Panel.width, maxWidth: Panel.width,
               minHeight: Panel.minHeight, maxHeight: .infinity)
        // 内容顶到窗口上缘，别让标题栏白白占 28pt
        .ignoresSafeArea()
        // 头部块：比内容区亮一档。层次靠材质差异，不靠多画几条线
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
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
        .onReceive(NotificationCenter.default.publisher(for: .phDelete)) { _ in
            guard current != nil else { return }
            model.deleteCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phPin)) { _ in
            guard current != nil else { return }
            model.togglePinCurrent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phClose)) { _ in onClose() }
        // 每次打开面板都是一次新的「找」：回到第一条
        .onReceive(NotificationCenter.default.publisher(for: .phPanelWillShow)) { _ in model.resetForPresentation() }
        .onReceive(NotificationCenter.default.publisher(for: .phQuickPaste)) { note in
            guard let index = note.object as? Int, index < results.count else { return }
            onPaste(results[index])
        }
        .onChange(of: store.displayed) { _, _ in model.rebuildSections() }
    }

    private var current: ClipItem? { model.current }

    // MARK: - 搜索

    private var searchBar: some View {
        HStack(spacing: Rhythm.l) {
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
                // 不用 pinnedViews：悬浮标题盖在视口顶部，而 scrollTo 的「最小滚动」
                // 只保证行进入 ScrollView 边界、不知道上面还浮着一层标题——
                // 滚到顶时第一条的上半截正好被压在标题下面（真机截图实锤）。
                // 标题随内容滚动，任何行都不会再被盖住。
                //
                // 分组标题也是一行：整个列表只有一个 ForEach、稳定 id。
                // 之前 ForEach(sections, id: \.offset) + Section 的组合里，置顶区
                // 连续生长时 SwiftUI 按 offset 复用分区视图、内容原地突变，
                // LazyVStack 的布局跟不上——行序错乱（⌘1 排到 ⌘2 下面）、
                // 标题丢失、部分行选不到，全是这一个错误源
                LazyVStack(spacing: Spec.rowSpacing) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .header(let title):
                            SectionHeader(title: title)
                        case .item(let item, let index):
                            row(item: item, index: index)
                        }
                    }
                }
                .padding(Spec.listPadding)
                // 橡皮筋位移放在内容上、不放在 ScrollView 上：
                // 放 ScrollView 会把滚动条一起推出去，看着像整个面板在晃
                .offset(y: bounce)
            }
            .onChange(of: safeSelection) { _, newValue in
                guard newValue < results.count else { return }
                // 不带 anchor：只滚最小位移。anchor: .center 每按一次都把行拉到正中，
                // 整片列表跟着滑——那是「抖」的根源
                let anim = Date().timeIntervalSince(model.lastMoveAt) < Motion.repeatThreshold
                    ? Motion.selectionFast
                    : Motion.selection
                withAnimation(anim) { proxy.scrollTo(results[newValue].id) }
            }
            .onChange(of: model.bounceTick) { _, _ in
                // 弹簧还没停就再次撞墙（按住方向键的 key repeat）不再重新推——
                // 每次都瞬间位移再回弹，动作永远叠不严，看起来就是抖。
                // 停稳后的下一次撞击照常弹
                guard bounce == 0 else { return }
                // 先瞬间推出去，再让弹簧把它拉回来——
                // 「推出去」本身不能有动画，否则撞墙那一下是软的
                bounce = CGFloat(model.bounceDirection) * Spec.bounceDistance
                withAnimation(Motion.bounce) { bounce = 0 }
            }
            .onChange(of: store.query) { _, _ in model.resetSelection() }
        }
        // 内容区比头部暗一档，两个材质一明一暗，区域自然分开
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .center) {
            if results.isEmpty { emptyState }
        }
    }

    /// 区域划分靠分组，不靠分割线：置顶 / 今天 / 昨天 / 更早。
    /// 分页与键盘导航按展平的 results 走；渲染把标题插进同一条流
    private var sections: [HistorySection] { model.sections }

    /// 扁平化后的列表内容：标题行 + 条目行，id 全局稳定
    private var entries: [ListEntry] {
        var out: [ListEntry] = []
        for section in sections {
            out.append(.header(section.title))
            for pair in section.items {
                out.append(.item(pair.item, pair.index))
            }
        }
        return out
    }

    private func row(item: ClipItem, index: Int) -> some View {
        RowView(item: item,
                index: index,
                query: store.query,
                selected: index == safeSelection,
                selectionSpace: selectionSpace,
                onPin: { model.togglePin(at: index) },
                onDelete: { model.delete(at: index) })
            .id(item.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onPaste(item) }
            .simultaneousGesture(TapGesture(count: 1).onEnded {
                model.select(index)
            })
            .onAppear {
                if index >= results.count - 8 { store.loadMore() }
            }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(store.totalCount == 0 ? L10n.noHistory : L10n.noMatch)
                .font(.system(size: Scale.field, weight: .medium))
            Text(store.totalCount == 0 ? L10n.copySomething : L10n.tryAnother)
                .font(.system(size: Scale.body))
                .foregroundStyle(Palette.meta)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Rhythm.xxl)
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
        .padding(.horizontal, Spec.listPadding + Rhythm.m)
        .padding(.vertical, Rhythm.l)
        // 不透明底：标题滚过缩略图行时文字不能透出底下内容
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 单行

struct RowView: View {
    let item: ClipItem
    let index: Int
    let query: String
    let selected: Bool
    /// 选中高亮的共享几何空间
    let selectionSpace: Namespace.ID
    var onPin: () -> Void
    var onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Rhythm.xl) {
            thumbnail

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
        .frame(height: Spec.thumb)
        .padding(.horizontal, Spec.rowPadding)
        .padding(.vertical, 5)
        .background(
            ZStack {
                // 悬停：就地渐变进出，它是「这里可以按」的承诺，不需要移动
                RoundedRectangle(cornerRadius: Spec.corner)
                    .fill(Color.primary.opacity(hovered && !selected ? Spec.hoverFill : 0))

                // 选中：一个挂了共享 id 的矩形。上下切换时 SwiftUI 把这块矩形
                // 从上一行的几何补间到这一行——高亮是真的在走，而不是两行各自淡入淡出。
                // 后者中间没有任何东西在移动，人眼对交叉淡化几乎无感，
                // 这就是「上下选中的感觉没了」的根因
                if selected {
                    RoundedRectangle(cornerRadius: Spec.corner)
                        .fill(Color.accentColor.opacity(Spec.selectFill))
                        .matchedGeometryEffect(id: Highlight.id,
                                               in: selectionSpace,
                                               properties: .frame)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
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
        .animation(Motion.hover, value: hovered)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb = item.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFill()
                // scaledToFill 会画出 frame 外，必须裁——不然宽图会探出去压住别行
                .frame(width: Spec.thumb, height: Spec.thumb)
                .clipShape(RoundedRectangle(cornerRadius: Spec.corner))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Spec.corner)
                    .fill(Color.primary.opacity(Spec.chipFill))
                Image(systemName: symbol)
                    .font(.system(size: Icon.thumb))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Spec.thumb, height: Spec.thumb)
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
