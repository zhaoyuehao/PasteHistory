import AppKit

/// A borderless window must explicitly accept key status for search and shortcuts.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func applyPresentation(tree: Bool) {
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
