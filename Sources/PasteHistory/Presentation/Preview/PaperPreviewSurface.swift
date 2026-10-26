import AppKit

/// A live, selectable document in fixed logical coordinates. Scaling the parent
/// coordinate system enlarges text and images together without a bitmap snapshot
/// or reflowing paragraphs on every pinch event.
final class PaperPreviewSurface: NSView {
    let document: NSView
    private let documentMask = CAShapeLayer()
    var readingSize: NSSize? { didSet { needsLayout = true } }

    init(document: NSView) {
        self.document = document
        super.init(frame: document.frame)
        document.autoresizingMask = []
        wantsLayer = true
        document.wantsLayer = true
        addSubview(document)
        document.layer?.mask = documentMask
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        let logical = readingSize ?? frame.size
        if bounds.size != logical { setBoundsSize(logical) }
        if document.frame != bounds { document.frame = bounds }
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Only the retained parent renderer draws the edge and hanging hole.
        // Keep text selection native inside the fixed logical reading layout.
        documentMask.path = CGPath(rect: NSRect(x: 2, y: document.isFlipped ? 10 : 2,
            width: max(0,bounds.width-4), height: max(0,bounds.height-12)), transform: nil)
        CATransaction.commit()
    }
}

/// AppKit receives magnify events for a non-key preview but does not begin its
/// view recognizers until a click makes it key. Route only this window's events
/// before that focus gate; the search editor remains the keyboard destination.
class PaperPreviewPanel: NSPanel {
    var acceptsKeyboardFocus = true
    var onCollapse: (() -> Void)?
    private var clickOrigin: NSPoint?
    private var clickGeneration = 0
    private weak var clickedText: NSTextView?
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Bool)?
    private var interactionMonitor: Any?
    var handlesPaperPinch: Bool { interactionMonitor != nil }
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }

    func beginPaperInteraction() {
        cancelClick()
        guard interactionMonitor == nil else { return }
        interactionMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.magnify, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            self.trackClick(event)
            if event.type == .magnify,
               self.routeMagnification(from: event.window, at: event.locationInWindow,
                                       delta: event.magnification, phase: event.phase) {
                return nil // One zoom owner; do not also magnify a descendant.
            }
            return event // Text selection and scrolling keep their native events.
        }
    }
    func endPaperInteraction() {
        cancelClick()
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
        interactionMonitor = nil
    }
    private func cancelClick() {
        clickOrigin = nil
        clickedText = nil
        clickGeneration += 1
    }

    /// Observe the completed click, including mouse-up consumed by NSTextView's
    /// tracking loop. Never intercept selection drags or scrollbar interaction.
    func trackClick(_ event: NSEvent) {
        let point = event.locationInWindow
        let inside = event.window === self && isVisible && alphaValue > 0 && !ignoresMouseEvents
            && NSRect(origin: .zero, size: frame.size).contains(point)
        switch event.type {
        case .leftMouseDown:
            cancelClick()
            guard handlesPaperPinch, inside, event.clickCount == 1,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
                  let contentView else { return }
            let hitPoint = contentView.superview?.convert(point, from: nil) ?? point
            var hit = contentView.hitTest(hitPoint)
            while let view = hit {
                if view is NSControl { return }
                if let text = view as? NSTextView { clickedText = text }
                hit = view.superview
            }
            clickOrigin = point
        case .leftMouseDragged:
            if let origin = clickOrigin,
               hypot(point.x - origin.x, point.y - origin.y) > 5 { cancelClick() }
        case .leftMouseUp:
            guard inside, event.clickCount == 1, let origin = clickOrigin,
                  hypot(point.x - origin.x, point.y - origin.y) <= 5 else {
                cancelClick()
                return
            }
            clickOrigin = nil
            let generation = clickGeneration
            // Let native selection finish before deciding whether this was a click.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.clickGeneration == generation, self.handlesPaperPinch,
                      self.isVisible, !self.ignoresMouseEvents,
                      (self.clickedText?.selectedRange().length ?? 0) == 0 else { return }
                self.cancelClick()
                self.onCollapse?()
            }
        case .scrollWheel, .magnify, .keyDown:
            cancelClick()
        default:
            break
        }
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
