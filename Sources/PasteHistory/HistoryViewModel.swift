import Foundation
import SwiftUI

struct HistorySection {
    let title: String
    let items: [(item: ClipItem, index: Int)]
}

/// Coordinates list state and user actions for the history panel.
@MainActor
final class HistoryViewModel: ObservableObject {
    let store: ClipStore
    @Published private(set) var selection = 0
    @Published private(set) var sections: [HistorySection] = []

    /// 搜索词已换、结果集还没刷新（防抖 0.25s）：下一次重排回到第一条，
    /// 而不是按 id 跟着旧选中漂——搜索永远是一次新的「找」
    private var resetsToTopOnRebuild = false

    /// 渲染、键盘、⌘1–9 共用的唯一顺序：置顶在前，其余按时间倒序。
    /// 之前只有渲染把置顶提到最前，键盘仍按时间顺序走，
    /// 于是视觉第一行和选中项不是同一条，⌘1 粘的也不是看到的第一条。
    @Published private(set) var ordered: [ClipItem] = []

    /// 撞到边界的次数。列表按住它做一次橡皮筋回弹，
    /// 每次递增是因为「连撞两次」也要弹两次——只发状态不发事件的话，
    /// 第二次撞墙 selection 没变、onChange 不触发，就成了哑巴
    @Published private(set) var bounceTick = 0
    /// 回弹方向：+1 往下撞底，-1 往上撞顶
    @Published private(set) var bounceDirection: Int = 1

    var lastMoveAt = Date.distantPast

    init(store: ClipStore) {
        self.store = store
        rebuildSections()
    }

    var results: [ClipItem] { ordered }
    var safeSelection: Int { results.isEmpty ? 0 : min(max(selection, 0), results.count - 1) }
    var current: ClipItem? { safeSelection < results.count ? results[safeSelection] : nil }

    /// 上下移动选中项。
    ///
    /// 到边界时 selection 不会变，`onChange(of: safeSelection)` 也就不会触发——
    /// 所以撞墙必须自己发一次事件（bounceTick），否则「到底了」是彻底的静默。
    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let now = Date()
        let fast = now.timeIntervalSince(lastMoveAt) < Motion.repeatThreshold
        lastMoveAt = now
        let next = min(max(safeSelection + delta, 0), results.count - 1)

        guard next != safeSelection else {
            bounceDirection = delta > 0 ? 1 : -1
            bounceTick += 1
            return
        }

        withAnimation(fast ? Motion.selectionFast : Motion.selection) { selection = next }
    }

    func select(_ index: Int) {
        guard !results.isEmpty else { return }
        // 鼠标点击也要走同一条弹簧，不然键盘和鼠标是两套手感
        withAnimation(Motion.selection) { selection = min(max(index, 0), results.count - 1) }
    }

    /// 每次打开面板都是一次新的「找」：回到第一条
    func resetForPresentation() {
        selection = 0
    }

    /// 换搜索词：结果集变了，重新扫
    func resetSelection() {
        selection = 0
        resetsToTopOnRebuild = true
    }

    func deleteCurrent() {
        guard let item = current else { return }
        store.remove(id: item.id)
        selection = max(0, safeSelection - 1)
        rebuildSections()
    }

    func togglePinCurrent() {
        guard let item = current else { return }
        store.togglePin(id: item.id)
        rebuildSections()
    }

    func togglePin(at index: Int) {
        guard index < ordered.count else { return }
        store.togglePin(id: ordered[index].id)
        rebuildSections()
    }

    func delete(at index: Int) {
        guard index < ordered.count else { return }
        store.remove(id: ordered[index].id)
        selection = max(0, min(selection, ordered.count - 1))
        rebuildSections()
    }

    func rebuildSections() {
        // 选中是「这一条」的属性，不是「第几个」。重排（置顶/取消置顶、
        // 面板开着时新拷贝进来、同步导入）会让索引全体位移，selection 留在
        // 原索引就指到了别的条目上——置顶那条的高亮随 matchedGeometryEffect
        // 旧属主一起消失，看起来就是「置顶后没有选中了」。重排后按 id 找回同一条
        let selectedId = current?.id
        var pinned: [ClipItem] = []
        var rest: [ClipItem] = []
        for item in store.displayed {
            if item.pinned { pinned.append(item) } else { rest.append(item) }
        }
        ordered = pinned + rest

        var grouped: [HistorySection] = []
        if !pinned.isEmpty {
            grouped.append(HistorySection(title: L10n.pinned,
                                          items: pinned.enumerated().map { (item: $0.element, index: $0.offset) }))
        }

        let offset = pinned.count
        var currentTitle: String?
        var bucket: [(item: ClipItem, index: Int)] = []
        for pair in rest.enumerated() {
            let title = Self.dayTitle(pair.element.createdAt)
            if title != currentTitle {
                if let currentTitle, !bucket.isEmpty {
                    grouped.append(HistorySection(title: currentTitle, items: bucket))
                    bucket = []
                }
                currentTitle = title
            }
            bucket.append((item: pair.element, index: offset + pair.offset))
        }
        if let currentTitle, !bucket.isEmpty {
            grouped.append(HistorySection(title: currentTitle, items: bucket))
        }
        sections = grouped

        if resetsToTopOnRebuild {
            resetsToTopOnRebuild = false
            selection = 0
        } else if let selectedId, let idx = ordered.firstIndex(where: { $0.id == selectedId }) {
            selection = idx
        } else {
            // 选中条目不在新结果集里（被删除 / 被过滤掉）：夹回有效范围
            selection = safeSelection
        }
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.today }
        if calendar.isDateInYesterday(date) { return L10n.yesterday }
        return L10n.earlier
    }
}
