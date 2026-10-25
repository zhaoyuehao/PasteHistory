import AppKit

/// Native scrolling for both presentations. List previews allow document zoom;
/// tree previews disable it because their window scales the whole live paper.
class PreviewZoomScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        wantsLayer = true
        layer?.masksToBounds = true
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        minMagnification = 0.5
        maxMagnification = 4
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func resetViewport() {
        magnification = 1
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }
}
