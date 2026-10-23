import AppKit

/// A live, selectable document in fixed logical coordinates. Scaling the parent
/// coordinate system enlarges text and images together without a bitmap snapshot
/// or reflowing paragraphs on every pinch event.
final class PaperPreviewSurface: NSView, NSGestureRecognizerDelegate {
    let document: NSView
    private var drawingScale: CGFloat = 0
    private(set) lazy var paperPinch = NSMagnificationGestureRecognizer(target: self, action: #selector(pinch(_:)))
    var readingSize: NSSize? {
        didSet {
            paperPinch.isEnabled = readingSize != nil
            needsLayout = true
        }
    }

    init(document: NSView) {
        self.document = document
        super.init(frame: document.frame)
        document.autoresizingMask = []
        addSubview(document)
        paperPinch.delegate = self
        paperPinch.delaysMagnificationEvents = true
        paperPinch.isEnabled = false
        addGestureRecognizer(paperPinch)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }

    @objc private func pinch(_ gesture: NSMagnificationGestureRecognizer) {
        let phase: NSEvent.Phase
        switch gesture.state {
        case .began: phase = .began
        case .changed: phase = .changed
        case .ended: phase = .ended
        case .cancelled, .failed: phase = .cancelled
        default: return
        }
        let delta = gesture.magnification
        gesture.magnification = 0
        (window as? PaperPreviewPanel)?.magnifyPaper(by: delta, phase: phase)
    }

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

/// Gesture actions are scoped to this window. Let AppKit dispatch native gesture
/// events normally so the surface's recognizer can recognize across descendants.
final class PaperPreviewPanel: NSPanel {
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    @discardableResult
    func magnifyPaper(by delta: CGFloat, phase: NSEvent.Phase) -> Bool {
        onMagnify?(delta, phase) ?? false
    }
}
