import SwiftUI

struct IvoryTreeView: View {
    @ObservedObject var model: HistoryViewModel
    var onPaste: (ClipItem) -> Void
    @State private var resetToken = 0
    @State private var unavailable = false
    private var pageStart: Int { model.safeSelection / 6 * 6 }
    private var pageEnd: Int { min(pageStart + 6, model.results.count) }
    private var entries: [IvoryTreeEntry] {
        guard pageStart < pageEnd else { return [] }
        return (pageStart..<pageEnd).map {
            IvoryTreeEntry(id: model.results[$0].id, title: model.results[$0].summary, index: $0)
        }
    }

    var body: some View {
        IvoryTreeCanvas(entries: entries, selectedID: model.current?.id, resetToken: resetToken,
                        unavailable: $unavailable, onSelect: select, onActivate: activate)
            .accessibilityLabel(L10n.wishTree)
            .accessibilityValue(model.current?.summary ?? L10n.noMatch)
            .onReceive(NotificationCenter.default.publisher(for: .phResetTree)) { _ in resetToken += 1 }
            .onChange(of: unavailable) { _, failed in
                // Preserve access to history if the resource cannot be loaded.
                if failed { NotificationCenter.default.post(name: .phToggleTree, object: nil) }
            }
        .onAppear { loadMoreIfNeeded() }
        .onChange(of: model.safeSelection) { _, _ in loadMoreIfNeeded() }
        .onChange(of: model.results.count) { _, _ in loadMoreIfNeeded() }
    }

    private func select(_ id: UUID) {
        if let index = model.results.firstIndex(where: { $0.id == id }) { model.select(index) }
    }
    private func activate(_ id: UUID) {
        if let item = model.results.first(where: { $0.id == id }) { onPaste(item) }
    }
    private func loadMoreIfNeeded() {
        if pageEnd >= model.results.count - 8 { model.store.loadMore() }
    }
}

private struct IvoryTreeCanvas: NSViewRepresentable {
    let entries: [IvoryTreeEntry]
    let selectedID: UUID?
    let resetToken: Int
    @Binding var unavailable: Bool
    let onSelect: (UUID) -> Void
    let onActivate: (UUID) -> Void
    final class Coordinator { var resetToken = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> IvoryTreeSceneView {
        // SwiftPM's generated accessor searches beside the executable; a packaged
        // macOS app keeps its resource bundle in Contents/Resources instead.
        let bundle: Bundle?
        if Bundle.main.bundleURL.pathExtension == "app" {
            bundle = Bundle.main.resourceURL.flatMap {
                Bundle(url: $0.appendingPathComponent("PasteHistory_PasteHistory.bundle"))
            }
        } else { bundle = Bundle.module }
        let view = IvoryTreeSceneView(url: bundle?.url(forResource: "ivory_tree", withExtension: "scn"))
        if view.loadError != nil { DispatchQueue.main.async { unavailable = true } }
        return view
    }
    func updateNSView(_ view: IvoryTreeSceneView, context: Context) {
        view.onSelect = onSelect
        view.onActivate = onActivate
        view.update(entries: entries, selectedID: selectedID)
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            view.resetView()
        }
    }
    static func dismantleNSView(_ view: IvoryTreeSceneView, coordinator: Coordinator) { view.stopRendering() }
}
