import AppKit

/// A borderless window must explicitly accept key status for search and shortcuts.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var treeOpacity: CGFloat = 1 {
        didSet {
            alphaValue = treeOpacity
            for island in islands {
                island.alphaValue = treeOpacity
            }
        }
    }
    var layoutEditing = false
    var prepareDrag: ((UUID) -> (() -> [NSPasteboardWriting]?)?)?
    var mergeCards: ((UUID, UUID) -> Bool)?
    var confirmPaper: ((UUID) -> Void)?
    var onDragUnavailable: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((NSDragOperation) -> Void)?
    var dragInProgress = false
    var expandedPaperID: UUID? {
        didSet {
            onPaperAppearanceChanged?()
        }
    }
    var onPaperAppearanceChanged: (() -> Void)?
    var onPaperLayout: (() -> Void)?
    var resumePaperUpdates: (() -> Void)?
    func finishPaperDrag(operation: NSDragOperation) {
        dragInProgress = false
        let resume = resumePaperUpdates
        resumePaperUpdates = nil
        resume?()
        onDragEnded?(operation)
    }
    func paper(for id: UUID) -> TreeInteractionPanel? {
        islands.first { $0.role == .paper && ($0.contentView as? TreePaperSurface)?.recordID == id && $0.isVisible }
    }
    private var presentsIslands = true
    private(set) var islands: [TreeInteractionPanel] = []
    func register(_ island: TreeInteractionPanel) { islands.append(island) }
    func unregister(_ island: TreeInteractionPanel) {
        removeChildWindow(island)
        islands.removeAll { $0 === island }
    }
    func showIslandIfNeeded(_ island: TreeInteractionPanel) {
        guard isVisible, presentsIslands else { return }
        island.alphaValue = treeOpacity
        positionSearch(island)
        if island.parent == nil { addChildWindow(island, ordered: .above) }
        // Apply after attachment: the owner may have changed level since the
        // portal was created, and an expanded paper sits one level above it.
        if island.role == .search {
            let searchLevel = NSWindow.Level(rawValue: level.rawValue + 2)
            if island.level != searchLevel { island.level = searchLevel }
        }
        if !island.isVisible { island.orderFrontRegardless() }
    }
    private func positionSearch(_ island: TreeInteractionPanel) {
        guard island.role == .search else { return }
        let target = TreeSearchLayout.frame(in: frame)
        if island.frame != target { island.setFrame(target, display: false) }
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        // Resize/move callbacks need not cause a SwiftUI portal layout pass.
        for island in islands { positionSearch(island) }
    }
    func focusSearch() {
        guard isVisible, presentsIslands, !layoutEditing,
              let search = islands.first(where: { $0.role == .search }) else { return }
        showIslandIfNeeded(search)
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
        cancelPaperClicks()
        for island in islands { island.orderOut(nil) }
    }
    override func orderOut(_ sender: Any?) {
        presentsIslands = false
        cancelPaperClicks()
        for island in islands { island.orderOut(sender) }
        super.orderOut(sender)
    }
    func cancelPaperClicks(except window: NSWindow? = nil) {
        for island in islands where island !== window {
            (island.contentView as? TreePaperSurface)?.cancelClick()
        }
    }
    func configureTree() {
        ignoresMouseEvents = true
        styleMask = [.borderless, .nonactivatingPanel]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        contentView?.wantsLayer = true
        contentView?.layer?.isOpaque = false
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        invalidateShadow()
    }
}
