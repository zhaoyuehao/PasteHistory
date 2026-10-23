import AppKit

/// Shared by the hanging card, its expanded face and the moving paper.
enum IvoryPaperStyle {
    static let fill = NSColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1)
    static let ink = NSColor(white: 0.16, alpha: 1)
    static let meta = NSColor(white: 0.36, alpha: 1)
    static let edge = NSColor(red: 0.66, green: 0.77, blue: 0.72, alpha: 1)
    static let radius: CGFloat = 4
    static let pinInset: CGFloat = 7
}

/// Screen-facing paper keeps the system font readable at every viewing angle.
/// A paper's suspension point always comes from the corresponding 3D branch.
final class IvoryTreePaperView: NSView {
    struct Attachment {
        let point: NSPoint
        let height: CGFloat
        let depth: CGFloat
    }
    private struct Card {
        var entry: IvoryTreeEntry
        var rect: NSRect
        var anchor: NSPoint
        var tilt: CGFloat
        var opacity: CGFloat = 1
        var fold: CGFloat = 1
    }
    private var entries: [IvoryTreeEntry] = []
    private var cards: [Card] = []
    private var outgoing: [Card] = []
    private var selectedID: UUID?
    private var images: [UUID: NSImage] = [:]
    private var turnStart: CFTimeInterval = 0
    private var turnDirection: CGFloat = 1
    private var selectionRect = NSRect.zero
    private var selectionTilt: CGFloat = 0
    private var heights: [UUID: CGFloat] = [:]
    private var lastGrowth: CGFloat = 1
    private var selectionFade: CGFloat = 1
    private(set) var isAnimating = false
    var onSelect: ((UUID) -> Void)?
    var onPreview: ((UUID) -> Void)?
    var layoutEditing = false
    private var islands: [UUID: TreeInteractionPanel] = [:]
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clearIslands() }
    }
    private func clearIslands() {
        for panel in islands.values { panel.detach() }
        islands.removeAll()
    }
    private func syncIslands() {
        guard let owner = window as? HistoryPanel else { clearIslands(); return }
        guard !owner.dragInProgress else {
            owner.resumePaperUpdates = { [weak self] in self?.syncIslands() }
            return
        }
        owner.onPaperAppearanceChanged = { [weak self] in self?.needsDisplay = true }
        let current = visuals()
        let ids = Set(current.map { $0.entry.id })
        for id in Array(islands.keys) where !ids.contains(id) {
            islands.removeValue(forKey: id)?.detach()
        }
        for card in current {
            let id = card.entry.id
            let panel: TreeInteractionPanel
            let surface: TreePaperSurface
            if let existing = islands[id], let view = existing.contentView as? TreePaperSurface {
                panel = existing; surface = view
            } else {
                panel = TreeInteractionPanel(owner: owner, role: .paper)
                surface = TreePaperSurface()
                panel.contentView = surface
                panel.title = "剪贴纸签"
                islands[id] = panel
            }
            // Rectangular paper footprint (including its small tilt and shadow).
            // Cords, branches and the rest of the desktop never acquire a window.
            let a = card.tilt * .pi / 180
            let center = NSPoint(x: card.rect.midX, y: card.rect.minY + IvoryPaperStyle.pinInset)
            panel.paperPin = owner.convertPoint(toScreen: convert(center, to: nil))
            let corners: [NSPoint] = [NSPoint(x: card.rect.minX, y: card.rect.minY),
                          NSPoint(x: card.rect.maxX, y: card.rect.minY),
                          NSPoint(x: card.rect.minX, y: card.rect.maxY),
                          NSPoint(x: card.rect.maxX, y: card.rect.maxY)]
            let points: [NSPoint] = corners.map { p in
                let dx = (p.x-center.x) * card.fold
                let dy = p.y-center.y
                return NSPoint(x: center.x + dx*cos(a) - dy*sin(a), y: center.y + dx*sin(a) + dy*cos(a))
            }
            let left = points.map(\.x).min()!, top = points.map(\.y).min()!
            let frame = NSRect(x: left-3, y: top-3,
                               width: points.map(\.x).max()!-left+6,
                               height: points.map(\.y).max()!-top+6)
            panel.setFrame(owner.convertToScreen(convert(frame, to: nil)), display: false)
            // Visible transitional papers consume a click without activating a new
            // record or accidentally clicking the app beneath the departing paper.
            panel.alphaValue = owner.expandedPaperID == id ? 0 : 1
            panel.enabled = card.opacity > 0.01 && owner.expandedPaperID != id
            surface.enabled = !layoutEditing && !isTurningPage && card.opacity > 0.9
                && cards.contains { $0.entry.id == id }
            surface.recordID = id
            surface.setAccessibilityLabel(card.entry.title)
            surface.setAccessibilityValue(card.entry.id == selectedID ? "已选中" : "")
            surface.paint = { [weak self] in
                guard let self, let ctx = NSGraphicsContext.current?.cgContext else { return }
                ctx.saveGState()
                ctx.translateBy(x: -frame.minX, y: -frame.minY)
                ctx.setAlpha(card.opacity)
                self.transform(card.rect, tilt: card.tilt, fold: card.fold, context: ctx)
                self.drawPaper(card)
                ctx.restoreGState()
            }
            surface.onSelect = { [weak self] in self?.onSelect?(id) }
            surface.onPreview = { [weak self] in self?.onPreview?(id) }
            surface.needsDisplay = true
            owner.showIslandIfNeeded(panel)
        }
        owner.onPaperLayout?()
    }

    var cardFrames: [UUID: NSRect] {
        Dictionary(uniqueKeysWithValues: cards.map { ($0.entry.id, $0.rect) })
    }
    var isTurningPage: Bool { CACurrentMediaTime() - turnStart < 0.28 }
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(entries: [IvoryTreeEntry], selectedID: UUID?, turnPage: Bool) {
        let accessibilityChanged = self.entries != entries || self.selectedID != selectedID
        if turnPage {
            // Freeze exactly what is currently visible. Fast input replaces the
            // transition instead of queuing old pages or reviving invisible cards.
            outgoing = Array(visuals().suffix(16))
            turnDirection = (entries.first?.index ?? 0) >= (self.entries.first?.index ?? 0) ? 1 : -1
            turnStart = CACurrentMediaTime()
            self.entries = entries
            heights = heights.filter { key, _ in entries.contains { $0.id == key } }
            let ids = Set((entries + outgoing.map(\.entry)).map(\.id))
            images = images.filter { ids.contains($0.key) }
            for entry in entries {
                if let data = entry.thumbnail { images[entry.id] = NSImage(data: data) }
            }
        }
        if self.selectedID != selectedID && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            selectionFade = 0
        }
        self.selectedID = selectedID
        if accessibilityChanged { rebuildAccessibility() }
    }
    func advance(attachments: [Attachment], sway: CGFloat, growth: CGFloat, dt: CGFloat) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let blend = 1 - pow(0.62, dt * 60)
        var next: [Card] = []
        var unsettled: CGFloat = 0
        let drops: [CGFloat] = [24, 33, 22, 37, 29, 21, 38, 26]
        let tilts: [CGFloat] = [-4, 3, -2, 5, 2, -5, 3, -3]
        for (slot, entry) in entries.enumerated() where slot < attachments.count {
            let a = attachments[slot]
            let width = min(IvoryTreeLayout.cardWidth, max(130, bounds.width * 0.32))
            let target =
                entry.id == selectedID ? IvoryTreeLayout.selectedHeight : IvoryTreeLayout.cardHeight
            let old = heights[entry.id] ?? IvoryTreeLayout.cardHeight
            let height = reduced ? target : old + (target - old) * blend
            heights[entry.id] = height
            unsettled += abs(target - height)
            var rect = NSRect(
                x: a.point.x - width / 2 + sway * 0.6, y: a.point.y + drops[slot % 8], width: width,
                height: height)
            rect.origin.x = max(8, min(bounds.width - width - 8, rect.minX))
            // Preserve the branch attachment, lengthening the cord only when two
            // papers overlap in projection (especially near a side-on view).
            for prior in next where rect.insetBy(dx: -6, dy: -6).intersects(prior.rect) {
                rect.origin.y = prior.rect.maxY + 9
            }
            rect.origin.y = max(8, min(bounds.height - height - 8, rect.minY))
            let opacity: CGFloat = reduced ? growth : (a.height <= 10 * (1 - pow(1 - growth, 2)) ? 1 : 0)
            next.append(
                Card(
                    entry: entry, rect: rect, anchor: a.point, tilt: reduced ? 0 : tilts[slot % 8] + sway,
                    opacity: opacity))
        }
        cards = next
        lastGrowth = growth
        if let selected = cards.first(where: { $0.entry.id == selectedID }) {
            let target = selected.rect.insetBy(dx: -2, dy: -2)
            if selectionRect == .zero || reduced {
                selectionRect = target
                selectionTilt = selected.tilt
            } else {
                let old = selectionRect
                selectionRect.origin.x += (target.minX - selectionRect.minX) * blend
                selectionRect.origin.y += (target.minY - selectionRect.minY) * blend
                selectionRect.size.width += (target.width - selectionRect.width) * blend
                selectionRect.size.height += (target.height - selectionRect.height) * blend
                selectionTilt += (selected.tilt - selectionTilt) * blend
                unsettled +=
                    abs(old.minX - target.minX) + abs(old.minY - target.minY)
                    + abs(old.height - target.height) + abs(selectionTilt - selected.tilt)
            }
        }
        selectionFade = min(1, selectionFade + dt / 0.15)
        if !isTurningPage { outgoing.removeAll() }
        isAnimating = isTurningPage || unsettled > 0.05 || selectionFade < 1
        syncIslands()
        needsDisplay = true
    }
    private func visuals() -> [Card] {
        let elapsed = CGFloat(CACurrentMediaTime() - turnStart)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var result: [Card] = []
        if elapsed < 0.14 {
            for var card in outgoing {
                let p = min(1, elapsed / 0.14)
                card.opacity *= 1 - p
                if !reduced {
                    card.fold *= max(0.02, cos(p * .pi / 2))
                    card.rect.origin.x -= turnDirection * 8 * p
                }
                result.append(card)
            }
        }
        for (slot, var card) in cards.enumerated() {
            let p = max(0, min(1, (elapsed - CGFloat(slot) * 0.006) / 0.23))
            card.opacity *= reduced ? min(1, elapsed / 0.15) : p
            if !reduced && p < 1 {
                card.fold = max(0.025, sin(p * .pi / 2))
                card.tilt += turnDirection * 5 * sin(p * .pi)
            }
            result.append(card)
        }
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let visuals = visuals()
        for card in visuals where card.opacity > 0.01 {
            context.saveGState()
            context.setAlpha(card.opacity)
            let cord = NSBezierPath()
            cord.move(to: card.anchor)
            let hole = NSPoint(x: card.rect.midX, y: card.rect.minY + 7)
            cord.curve(
                to: hole, controlPoint1: NSPoint(x: card.anchor.x, y: (card.anchor.y + hole.y) / 2),
                controlPoint2: NSPoint(x: hole.x, y: hole.y - 10))
            NSColor(red: 0.80, green: 0.76, blue: 0.66, alpha: 0.95).setStroke()
            cord.lineWidth = 1
            cord.stroke()
            NSBezierPath(ovalIn: NSRect(x: card.anchor.x - 2, y: card.anchor.y - 2, width: 4, height: 4))
                .stroke()
            transform(card.rect, tilt: card.tilt, fold: card.fold, context: context)
            // Outgoing cards are decoration only; only the current page owns input.
            if !(window is HistoryPanel) {
                drawPaper(card)
            }
            context.restoreGState()
        }
        if let card = cards.first(where: { $0.entry.id == selectedID }), card.opacity > 0,
           (window as? HistoryPanel)?.expandedPaperID != card.entry.id {
            context.saveGState()
            context.setAlpha(
                min(1, CGFloat(CACurrentMediaTime() - turnStart) / 0.23) * card.opacity * selectionFade)
            transform(selectionRect, tilt: selectionTilt, fold: 1, context: context)
            IvoryPaperStyle.edge.setStroke()
            let border = NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5)
            border.lineWidth = 1.5
            border.stroke()
            context.restoreGState()
        }
    }
    private func transform(_ rect: NSRect, tilt: CGFloat, fold: CGFloat, context: CGContext) {
        context.translateBy(x: rect.midX, y: rect.minY + 7)
        context.rotate(by: tilt * .pi / 180)
        context.scaleBy(x: fold, y: 1)
        context.translateBy(x: -rect.midX, y: -rect.minY - 7)
    }
    private func drawPaper(_ card: Card) {
        let rect = card.rect
        let selected = card.entry.id == selectedID
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.24)
        shadow.shadowBlurRadius = selected ? 9 : 5
        shadow.shadowOffset = NSSize(width: 1, height: 3)
        shadow.set()
        (selected
            ? IvoryPaperStyle.fill
            : NSColor(red: 0.79, green: 0.77, blue: 0.71, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.36, alpha: 0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 1.7, y: rect.minY + 5.3, width: 3.4, height: 3.4))
            .fill()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let source = card.entry.source.isEmpty ? "—" : card.entry.source
        let meta =
            String(format: "%02d", card.entry.index + 1) + (card.entry.pinned ? " · ↟ " : " · ") + source
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 0.31, alpha: 1), .paragraphStyle: style,
        ]
        (meta as NSString).draw(
            in: NSRect(x: rect.minX + 10, y: rect.minY + 12, width: rect.width - 20, height: 15),
            withAttributes: metaAttributes)
        var body = NSRect(
            x: rect.minX + 10, y: rect.minY + 31, width: rect.width - 20, height: rect.height - 37)
        if let image = images[card.entry.id] {
            let thumb = NSRect(x: rect.maxX - 54, y: body.minY, width: 44, height: min(52, body.height))
            let ratio = min(
                thumb.width / max(1, image.size.width), thumb.height / max(1, image.size.height))
            let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(
                in: NSRect(
                    x: thumb.midX - size.width / 2, y: thumb.midY - size.height / 2, width: size.width,
                    height: size.height), from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: nil)
            body.size.width -= 51
        }
        if selected && !card.entry.date.isEmpty { body.size.height -= 15 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (String(card.entry.title.prefix(500)) as NSString).draw(
            with: body, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.16, alpha: 1),
                .paragraphStyle: paragraph,
            ])
        if selected && !card.entry.date.isEmpty {
            (card.entry.date as NSString).draw(
                in: NSRect(x: rect.minX + 10, y: rect.maxY - 19, width: rect.width - 20, height: 14),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.36, alpha: 1),
                ])
        }
    }
    func entryID(at point: NSPoint) -> UUID? {
        // Do not let a click on a departing title activate the incoming record.
        // Keyboard selection/paste still takes effect immediately through the model.
        guard CACurrentMediaTime() - turnStart >= 0.14 else { return nil }
        let ordered = Array(visuals().suffix(cards.count)).sorted {
            ($0.entry.id == selectedID ? 1 : 0) < ($1.entry.id == selectedID ? 1 : 0)
        }
        for card in ordered.reversed() where card.opacity > 0.01 {
            let center = NSPoint(x: card.rect.midX, y: card.rect.minY + 7)
            let a = -card.tilt * .pi / 180
            let dx = point.x - center.x
            let dy = point.y - center.y
            let p = NSPoint(
                x: center.x + (dx * cos(a) - dy * sin(a)) / max(0.025, card.fold),
                y: center.y + dx * sin(a) + dy * cos(a))
            if card.rect.contains(p) { return card.entry.id }
        }
        return nil
    }
    private func rebuildAccessibility() {
        if window is HistoryPanel { setAccessibilityChildren([]); return }
        let children = entries.map { entry -> IvoryPaperAccessibility in
            let item = IvoryPaperAccessibility()
            item.setAccessibilityRole(.button)
            item.setAccessibilityEnabled(true)
            item.setAccessibilityLabel(entry.title)
            item.setAccessibilityValue(entry.source)
            item.setAccessibilityParent(self)
            item.action = { [weak self] in self?.onSelect?(entry.id) }
            return item
        }
        setAccessibilityElement(false)
        setAccessibilityChildren(children)
    }
}
private final class IvoryPaperAccessibility: NSAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        action?()
        return true
    }
}

/// Native dragging owns the pointer after the threshold. The payload is captured
/// from the pressed record, never from the changing keyboard selection.
final class TreePaperSurface: NSView, NSDraggingSource {
    var recordID: UUID?
    var paint: (() -> Void)?
    var onSelect: (() -> Void)?
    var onPreview: (() -> Void)?
    var enabled = true { didSet { setAccessibilityEnabled(enabled) } }
    private var dragPayload: (() -> [NSPasteboardWriting]?)?
    private var downEvent: NSEvent?
    private var dragOwner: HistoryPanel?
    private var down = NSPoint.zero
    private var dragged = false
    private var selectionAtDown: (() -> Void)?
    private var previewAtDown: (() -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) { paint?() }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }; onSelect?(); return true
    }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        guard let owner = (window as? TreeInteractionPanel)?.owner, !owner.layoutEditing else { return }
        downEvent = event
        dragPayload = recordID.flatMap { owner.prepareDrag?($0) }
        down = event.locationInWindow
        dragged = false
        selectionAtDown = onSelect
        previewAtDown = onPreview
        (window as? TreeInteractionPanel)?.owner?.focusSearch()
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, window?.isVisible == true, !dragged, let downEvent,
              let owner = (window as? TreeInteractionPanel)?.owner, !owner.layoutEditing,
              hypot(event.locationInWindow.x-down.x, event.locationInWindow.y-down.y) > 5 else { return }
        dragged = true
        guard let writers = dragPayload?(), !writers.isEmpty else { owner.onDragUnavailable?(); return }
        let image = paperImage()
        let items = writers.enumerated().map { index, writer in
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(bounds.offsetBy(dx: CGFloat(index) * 3, dy: CGFloat(index) * 3), contents: image)
            return item
        }
        dragOwner = owner // retain the source window through target activation and cancellation
        owner.dragInProgress = true
        owner.onDragBegan?()
        let session = beginDraggingSession(with: items, event: downEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
    func paperImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocusFlipped(true)
        paint?()
        image.unlockFocus()
        return image
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let owner = dragOwner
        dragOwner = nil
        downEvent = nil; dragPayload = nil; selectionAtDown = nil; previewAtDown = nil
        owner?.finishPaperDrag(operation: operation)
    }
    override func mouseUp(with event: NSEvent) {
        defer { selectionAtDown = nil; previewAtDown = nil; downEvent = nil; dragPayload = nil }
        guard enabled, window?.isVisible == true, !dragged, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount == 2 { previewAtDown?() } else { selectionAtDown?() }
    }
}
