import Foundation
import Combine

/// Coordinates tree selection and user actions for the history panel.
@MainActor
final class HistoryViewModel: ObservableObject {
    let store: ClipStore
    @Published private(set) var selection = 0

    /// 搜索词已换、结果集还没刷新（防抖 0.25s）：下一次重排回到第一条，
    /// 而不是按 id 跟着旧选中漂——搜索永远是一次新的「找」
    private var resetsToTopOnRebuild = false

    /// 渲染、键盘、⌘1–9 共用的唯一顺序：置顶在前，其余按时间倒序。
    /// 之前只有渲染把置顶提到最前，键盘仍按时间顺序走，
    /// 于是视觉第一行和选中项不是同一条，⌘1 粘的也不是看到的第一条。
    @Published private(set) var ordered: [ClipItem] = []

    /// 撞到边界的次数。预览用它做一次橡皮筋回弹，
    /// 每次递增是因为「连撞两次」也要弹两次——只发状态不发事件的话，
    /// 第二次撞墙 selection 没变、onChange 不触发，就成了哑巴
    @Published private(set) var bounceTick = 0
    /// 回弹方向：+1 撞顶内容向下沉，-1 撞底内容向上顶——跟系统橡皮筋同向。
    /// 撞顶时往上蹿会把第一行更狠地推出视口，看起来像故障而不是反馈
    @Published private(set) var bounceDirection: Int = 1

    /// 每次打开重置选中并触发树的呈现。
    @Published private(set) var presentationTick = 0

    init(store: ClipStore) {
        self.store = store
        rebuildResults()
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
        let next = min(max(safeSelection + delta, 0), results.count - 1)

        guard next != safeSelection else {
            bounceDirection = delta > 0 ? -1 : 1
            bounceTick += 1
            return
        }

        selection = next
    }

    func select(_ index: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(index, 0), results.count - 1)
    }

    /// 每次打开面板都是一次新的「找」：回到第一条，视口也回顶
    func resetForPresentation() {
        selection = 0
        presentationTick += 1
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
        rebuildResults()
    }

    func togglePinCurrent() {
        guard let item = current else { return }
        store.togglePin(id: item.id)
        rebuildResults()
    }

    func rebuildResults() {
        // 选中是「这一条」的属性，不是「第几个」。重排（置顶/取消置顶、
        // 面板开着时新拷贝进来、同步导入）会让索引全体位移，selection 留在
        // 原索引就指到了别的条目上。重排后按 id 找回同一条
        let selectedId = current?.id
        var pinned: [ClipItem] = []
        var rest: [ClipItem] = []
        for item in store.displayed {
            if item.pinned { pinned.append(item) } else { rest.append(item) }
        }
        ordered = pinned + rest

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

}
