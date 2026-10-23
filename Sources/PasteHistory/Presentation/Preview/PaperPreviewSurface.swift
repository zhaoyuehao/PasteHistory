import AppKit

/// A live, selectable document in fixed logical coordinates. Scaling the parent
/// coordinate system enlarges text and images together without a bitmap snapshot
/// or reflowing paragraphs on every pinch event.
final class PaperPreviewSurface: NSView {
    let document: NSView
    private var drawingScale: CGFloat = 0
    var readingSize: NSSize? { didSet { needsLayout = true } }

    init(document: NSView) {
        self.document = document
        super.init(frame: document.frame)
        document.autoresizingMask = []
        addSubview(document)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        let logical = readingSize ?? frame.size
        if bounds.size != logical { setBoundsSize(logical) }
        if document.frame != bounds { document.frame = bounds }
        super.layout()
        let scale = (window?.backingScaleFactor ?? 2) * frame.width / max(1, bounds.width)
        if abs(scale - drawingScale) > 0.001 {
            drawingScale = scale
            // SwiftUI's cached header/footer layers otherwise stretch their old
            // pixels while the native text view redraws sharply. Refresh both at
            // the physical reading resolution, including non-integer magnification.
            func redraw(_ layer: CALayer) {
                layer.contentsScale = scale
                layer.setNeedsDisplay()
                layer.sublayers?.forEach(redraw)
            }
            if let layer = document.layer { redraw(layer) }
            document.needsDisplay = true
        }
    }
}

/// Magnification is intercepted only for this window, before an image or text
/// scroll view can consume it. No click, key-window change or global monitor.
final class PaperPreviewPanel: NSPanel {
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .magnify, magnifyPaper(by: event.magnification, phase: event.phase) { return }
        super.sendEvent(event)
    }
    @discardableResult
    func magnifyPaper(by delta: CGFloat, phase: NSEvent.Phase) -> Bool {
        onMagnify?(delta, phase) ?? false
    }
}
