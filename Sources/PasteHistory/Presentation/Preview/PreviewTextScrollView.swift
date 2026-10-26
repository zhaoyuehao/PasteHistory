import AppKit

/// Reset after SwiftUI supplies the reading viewport. Scrolling an NSTextView
/// before its first layout lets AppKit move the origin again as it sizes text.
final class PreviewTextScrollView: PreviewZoomScrollView {
    private var needsInitialScroll = false

    func resetTextViewport() {
        needsInitialScroll = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard needsInitialScroll, contentSize.width > 0, contentSize.height > 0,
              let text = documentView as? NSTextView else { return }
        needsInitialScroll = false
        // Lay out just the first viewport, preserving lazy layout for long clips.
        if let manager = text.layoutManager, let container = text.textContainer {
            manager.ensureLayout(forBoundingRect: NSRect(origin: .zero, size: contentSize), in: container)
        }
        text.setSelectedRange(NSRange(location: 0, length: 0))
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }
}
