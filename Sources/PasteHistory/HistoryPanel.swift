import AppKit

/// A borderless window must explicitly accept key status for search and shortcuts.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private(set) var treePresentation = false
    var layoutEditing = false
    private var presentsIslands = true
    private(set) var islands: [TreeInteractionPanel] = []
    func register(_ island: TreeInteractionPanel) { islands.append(island) }
    func unregister(_ island: TreeInteractionPanel) {
        removeChildWindow(island)
        islands.removeAll { $0 === island }
    }
    func showIslandIfNeeded(_ island: TreeInteractionPanel) {
        guard isVisible, treePresentation, presentsIslands else { return }
        if island.parent == nil { addChildWindow(island, ordered: .above) }
        if !island.isVisible { island.orderFrontRegardless() }
    }
    func focusSearch() {
        guard let search = islands.first(where: { $0.role == .search && $0.isVisible }) else { return }
        search.makeKey()
        guard !(search.firstResponder is NSTextView) else { return }
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        search.contentView?.layoutSubtreeIfNeeded()
        if let content = search.contentView, let input = field(in: content) {
            search.makeFirstResponder(input)
        }
    }
    override func orderFrontRegardless() {
        presentsIslands = true
        super.orderFrontRegardless()
        for island in islands { showIslandIfNeeded(island) }
    }
    func suspendIslands() {
        presentsIslands = false
        for island in islands { island.orderOut(nil) }
    }
    override func orderOut(_ sender: Any?) {
        presentsIslands = false
        for island in islands { island.orderOut(sender) }
        super.orderOut(sender)
    }
    func applyPresentation(tree: Bool) {
        treePresentation = tree
        ignoresMouseEvents = tree
        if !tree { for island in islands { island.orderOut(nil) } }

        styleMask = tree
            ? [.borderless, .nonactivatingPanel]
            : [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isOpaque = !tree
        backgroundColor = tree ? .clear : .windowBackgroundColor
        hasShadow = !tree
        isMovableByWindowBackground = !tree
        contentView?.wantsLayer = true
        contentView?.layer?.isOpaque = !tree
        contentView?.layer?.backgroundColor = tree ? NSColor.clear.cgColor : NSColor.windowBackgroundColor.cgColor
        invalidateShadow()
    }
}
