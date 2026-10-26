import SwiftUI

struct IvoryTreeView: View {
    @ObservedObject var model: HistoryViewModel
    var onPreview: () -> Void
    var layoutEditing: Bool
    var onRootPosition: (CGPoint) -> Void = { _ in }
    @State private var resetToken = 0
    @State private var unavailable = false
    private var pageStart: Int { model.safeSelection / IvoryTreeLayout.pageSize * IvoryTreeLayout.pageSize }
    private var pageEnd: Int { min(pageStart + IvoryTreeLayout.pageSize, model.results.count) }
    private var entries: [IvoryTreeEntry] {
        guard pageStart < pageEnd else { return [] }
        return (pageStart..<pageEnd).map {
            let item = model.results[$0]
            return IvoryTreeEntry(item: item, index: $0)
        }
    }

    var body: some View {
        IvoryTreeCanvas(
            entries: entries, selectedID: model.current?.id, resetToken: resetToken,
            presentationToken: model.presentationTick, onRootPosition: onRootPosition,
            unavailable: $unavailable, onSelect: select, onPreview: preview, layoutEditing: layoutEditing
        )
        .accessibilityLabel(L10n.wishTree)
        .accessibilityValue(model.current?.summary ?? L10n.noMatch)
        .onReceive(NotificationCenter.default.publisher(for: .phResetTree)) { _ in resetToken += 1 }
        .onChange(of: unavailable) { _, failed in
            if failed { Toast.show(L10n.treeUnavailable, duration: 5) }
        }
        .onAppear { loadMoreIfNeeded() }
        .onChange(of: model.safeSelection) { _, _ in loadMoreIfNeeded() }
        .onChange(of: model.results.count) { _, _ in loadMoreIfNeeded() }
    }

    private func select(_ id: UUID) {
        if let index = model.results.firstIndex(where: { $0.id == id }) { model.select(index) }
    }
    private func preview(_ id: UUID) {
        select(id)
        onPreview()
    }
    private func loadMoreIfNeeded() {
        if pageEnd >= model.results.count - 8 { model.store.loadMore() }
    }
}

private struct IvoryTreeCanvas: NSViewRepresentable {
    let entries: [IvoryTreeEntry]
    let selectedID: UUID?
    let resetToken: Int
    let presentationToken: Int
    let onRootPosition: (CGPoint) -> Void
    @Binding var unavailable: Bool
    let onSelect: (UUID) -> Void
    let onPreview: (UUID) -> Void
    let layoutEditing: Bool
    final class Coordinator {
        var resetToken = 0
        var presentationToken = -1
        var root = CGPoint.zero
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> IvoryTreeSceneView {
        // SwiftPM's generated accessor searches beside the executable; a packaged
        // macOS app keeps its resource bundle in Contents/Resources instead.
        let bundle: Bundle?
        if Bundle.main.bundleURL.pathExtension == "app" {
            bundle = Bundle.main.resourceURL.flatMap {
                Bundle(url: $0.appendingPathComponent("PasteHistory_PasteHistory.bundle"))
            }
        } else {
            bundle = Bundle.module
        }
        let view = IvoryTreeSceneView(url: bundle?.url(forResource: "ivory_tree", withExtension: "scn"))
        if view.loadError != nil { DispatchQueue.main.async { unavailable = true } }
        return view
    }
    func updateNSView(_ view: IvoryTreeSceneView, context: Context) {
        view.onRootPosition = { point in
            guard abs(point.x - context.coordinator.root.x) + abs(point.y - context.coordinator.root.y) > 0.5
            else { return }
            context.coordinator.root = point
            DispatchQueue.main.async { onRootPosition(point) }
        }
        view.onSelect = onSelect
        view.onPreview = onPreview
        view.layoutEditing = layoutEditing
        view.update(entries: entries, selectedID: selectedID)
        if context.coordinator.presentationToken != presentationToken {
            context.coordinator.presentationToken = presentationToken
            view.present()
        }
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            view.resetView()
        }
    }
    static func dismantleNSView(_ view: IvoryTreeSceneView, coordinator: Coordinator) { view.stopRendering() }
}
