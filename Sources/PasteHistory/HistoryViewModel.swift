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
    var lastMoveAt = Date.distantPast

    init(store: ClipStore) {
        self.store = store
        rebuildSections()
    }

    var results: [ClipItem] { store.displayed }
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

    func resetSelection() { selection = 0 }

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

    func rebuildSections() {
        var grouped: [HistorySection] = []
        var pinned: [(ClipItem, Int)] = []
        var rest: [(ClipItem, Int)] = []
        for (index, item) in results.enumerated() {
            if item.pinned { pinned.append((item, index)) } else { rest.append((item, index)) }
        }
        if !pinned.isEmpty {
            grouped.append(HistorySection(title: L10n.pinned,
                                          items: pinned.map { (item: $0.0, index: $0.1) }))
        }
        var currentTitle: String?
        var bucket: [(ClipItem, Int)] = []
        for pair in rest {
            let title = Self.dayTitle(pair.0.createdAt)
            if title != currentTitle {
                if let currentTitle, !bucket.isEmpty {
                    grouped.append(HistorySection(title: currentTitle,
                                                  items: bucket.map { (item: $0.0, index: $0.1) }))
                    bucket = []
                }
                currentTitle = title
            }
            bucket.append(pair)
        }
        if let currentTitle, !bucket.isEmpty {
            grouped.append(HistorySection(title: currentTitle,
                                          items: bucket.map { (item: $0.0, index: $0.1) }))
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
