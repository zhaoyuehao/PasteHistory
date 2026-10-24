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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

/// AppKit receives magnify events for a non-key preview but does not begin its
/// view recognizers until a click makes it key. Route only this window's events
/// before that focus gate; the search editor remains the keyboard destination.
final class PaperPreviewPanel: NSPanel {
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Bool)?
    private var pinchMonitor: Any?
    var handlesPaperPinch: Bool { pinchMonitor != nil }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func beginPaperPinch() {
        guard pinchMonitor == nil else { return }
        pinchMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.routeMagnification(from: event.window, at: event.locationInWindow,
                                                   delta: event.magnification, phase: event.phase) else { return event }
            return nil // One owner; do not also zoom a descendant or deliver twice.
        }
    }
    func endPaperPinch() {
        if let pinchMonitor { NSEvent.removeMonitor(pinchMonitor) }
        pinchMonitor = nil
    }
    /// Exact window identity and physical window coordinates bound the input.
    /// Never redirect an event from another card, search window, or application.
    func routeMagnification(from source: NSWindow?, at point: NSPoint, delta: CGFloat, phase: NSEvent.Phase) -> Bool {
        guard handlesPaperPinch, source === self, isVisible, alphaValue > 0,
              !ignoresMouseEvents, NSRect(origin: .zero, size: frame.size).contains(point) else { return false }
        return magnifyPaper(by: delta, phase: phase)
    }
    @discardableResult
    func magnifyPaper(by delta: CGFloat, phase: NSEvent.Phase) -> Bool {
        onMagnify?(delta, phase) ?? false
    }
}
