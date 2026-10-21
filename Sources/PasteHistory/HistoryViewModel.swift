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

    /// 渲染、键盘、⌘1–9 共用的唯一顺序：置顶在前，其余按时间倒序。
    /// 之前只有渲染把置顶提到最前，键盘仍按时间顺序走，
    /// 于是视觉第一行和选中项不是同一条，⌘1 粘的也不是看到的第一条。
    @Published private(set) var ordered: [ClipItem] = []

    var lastMoveAt = Date.distantPast

    init(store: ClipStore) {
        self.store = store
        rebuildSections()
    }

    var results: [ClipItem] { ordered }
    var safeSelection: Int { results.isEmpty ? 0 : min(max(selection, 0), results.count - 1) }
    var current: ClipItem? { safeSelection < results.count ? results[safeSelection] : nil }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let now = Date()
        let fast = now.timeIntervalSince(lastMoveAt) < 0.2
        lastMoveAt = now
        let next = min(max(safeSelection + delta, 0), results.count - 1)
        if fast {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selection = next }
        } else {
            withAnimation(.easeOut(duration: 0.20)) { selection = next }
        }
    }

    func select(_ index: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(index, 0), results.count - 1)
    }

    /// 每次打开面板都是一次新的「找」：回到第一条
    func resetForPresentation() {
        selection = 0
    }

    /// 换搜索词：结果集变了，重新扫
    func resetSelection() {
        selection = 0
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
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.today }
        if calendar.isDateInYesterday(date) { return L10n.yesterday }
        return L10n.earlier
    }
}
