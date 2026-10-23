import SwiftUI

struct IvoryTreeView: View {
    @ObservedObject var model: HistoryViewModel
    var onPaste: (ClipItem) -> Void
    var onCopy: (ClipItem) -> Void
    var onPreview: () -> Void
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
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IvoryTreeCanvas(entries: entries, selectedID: model.current?.id, resetToken: resetToken,
                                unavailable: $unavailable, onSelect: select, onActivate: activate)
                    .accessibilityLabel(L10n.wishTree)
                    .accessibilityHint(L10n.treeHint)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.wishTree).font(.system(size: 15, weight: .medium))
                        Text(L10n.treeHint).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button { resetToken += 1 } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.plain).help(L10n.treeReset).accessibilityLabel(L10n.treeReset)
                }
                .foregroundStyle(.white).padding(16)
                if unavailable {
                    Text(L10n.treeUnavailable).padding().background(.regularMaterial).frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { model.select(max(0, pageStart - 6)) } label: { Image(systemName: "chevron.left") }
                        .disabled(pageStart == 0).accessibilityLabel(L10n.treePrevious)
                    Text(model.results.isEmpty ? "0 / 0" : "\(pageStart+1)–\(pageEnd) / \(model.results.count)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Button {
                        model.select(pageEnd)
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(pageEnd >= model.results.count).accessibilityLabel(L10n.treeNext)
                    Spacer()
                    if let item = model.current {
                        Button { model.togglePinCurrent() } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }
                            .help(L10n.pinItem).accessibilityLabel(L10n.pinItem)
                        Button { model.deleteCurrent() } label: { Image(systemName: "trash") }
                            .help(L10n.deleteItem).accessibilityLabel(L10n.deleteItem)
                    }
                }
                .buttonStyle(.borderless)
                if let item = model.current {
                    HStack(alignment: .top, spacing: 10) {
                        if let thumbnail = item.thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFill()
                                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.summary).font(.system(size: 13)).lineLimit(2)
                            Text(item.sourceApp ?? L10n.appName).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 48, alignment: .top)
                    HStack(spacing: 10) {
                        Button { model.move(-1) } label: { Image(systemName: "arrow.up") }
                            .disabled(model.safeSelection == 0).help(L10n.treePreviousItem).accessibilityLabel(L10n.treePreviousItem)
                        Button { model.move(1) } label: { Image(systemName: "arrow.down") }
                            .disabled(model.safeSelection+1 >= model.results.count).help(L10n.treeNextItem).accessibilityLabel(L10n.treeNextItem)
                        Spacer(minLength: 0)
                        Button(L10n.treePreview) { onPreview() }
                        Button(L10n.treeCopy) { onCopy(item) }
                        Button(L10n.treePaste) { onPaste(item) }.buttonStyle(.borderedProminent)
                    }.font(.system(size: 11))
                } else {
                    Text(model.store.query.isEmpty ? L10n.noHistory : L10n.noMatch)
                        .font(.system(size: 13)).frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
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
