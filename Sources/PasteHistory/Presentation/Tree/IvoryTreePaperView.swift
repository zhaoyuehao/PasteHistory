import AppKit

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
    private var faceCache: [UUID: (entry: IvoryTreeEntry, size: NSSize, selected: Bool, image: NSImage)] = [:]
    private var turnStart: CFTimeInterval = 0
    private var turnDirection: CGFloat = 1
    private var selectionRect = NSRect.zero
    private var selectionTilt: CGFloat = 0
    private var heights: [UUID: CGFloat] = [:]
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
        owner.onPaperAppearanceChanged = { [weak self] in
            // The selection outline belongs to the decorative tree window. Draw
            // it inside the same handoff group as the paper windows, not one frame later.
            self?.needsDisplay = true
            self?.displayIfNeeded()
        }
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
                panel.title = card.entry.isPermanent ? L10n.phoneSync : "剪贴纸签"
                islands[id] = panel
            }
            // Rectangular paper footprint (including its small tilt and shadow).
            // Cords, branches and the rest of the desktop never acquire a window.
            let a = card.tilt * .pi / 180
            let center = NSPoint(x: card.rect.midX, y: card.rect.minY + IvoryPaperStyle.pinInset)

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
            panel.paperPin = owner.convertPoint(toScreen: convert(center, to: nil))
            panel.paperSize = NSSize(width: card.rect.width * card.fold, height: card.rect.height)
            panel.paperAngle = -a
            let selected = card.entry.id == selectedID
            let color = selected ? IvoryPaperStyle.fill : NSColor(red: 0.79, green: 0.77, blue: 0.71, alpha: 1)
            let cached = faceCache[id]
            let image: NSImage
            if let cached, cached.entry == card.entry, cached.size == card.rect.size, cached.selected == selected {
                image = cached.image
            } else {
                image = NSImage(size: card.rect.size)
                image.lockFocusFlipped(true)
                NSGraphicsContext.current?.cgContext.translateBy(x: -card.rect.minX, y: -card.rect.minY)
                drawPaper(card)
                image.unlockFocus()
                faceCache[id] = (card.entry, card.rect.size, selected, image)
            }
            panel.paperColor = color
            panel.paperSnapshot = { image }
            if let pose = panel.paperPose {
                surface.present(image: image, pose: pose, canvas: panel.frame, color: color, opacity: card.opacity)
            }
            // Visible transitional papers consume a click without activating a new
            // record or accidentally clicking the app beneath the departing paper.
            panel.alphaValue = owner.expandedPaperID == id ? 0 : owner.treeOpacity
            panel.enabled = card.opacity > 0.01 && owner.expandedPaperID != id
            surface.enabled = !layoutEditing && (card.entry.isPermanent || !isTurningPage) && card.opacity > 0.9
                && cards.contains { $0.entry.id == id }
            surface.recordID = id
            surface.draggable = !card.entry.isPermanent
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
    var isTurningPage: Bool { CACurrentMediaTime() - turnStart < TreeMotion.pageDuration }
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(entries: [IvoryTreeEntry], selectedID: UUID?, turnPage: Bool) {
        let accessibilityChanged = self.entries != entries || self.selectedID != selectedID
        if turnPage {
            // Freeze exactly what is currently visible. Fast input replaces the
            // transition instead of queuing old pages or reviving invisible cards.
            outgoing = Array(visuals().filter { !$0.entry.isPermanent }.suffix(16))
            turnDirection = (entries.first(where: { !$0.isPermanent })?.index ?? 0) >= (self.entries.first(where: { !$0.isPermanent })?.index ?? 0) ? 1 : -1
            turnStart = self.entries.isEmpty ? 0 : CACurrentMediaTime()
            self.entries = entries
            heights = heights.filter { key, _ in entries.contains { $0.id == key } }
            let ids = Set((entries + outgoing.map(\.entry)).map(\.id))
            images = images.filter { ids.contains($0.key) }
            faceCache = faceCache.filter { ids.contains($0.key) }
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
    func finishEntrance() {
        turnStart = 0
        outgoing.removeAll()
    }
    func advance(attachments: [Attachment], sway: CGFloat, dt: CGFloat) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let blend = TreeMotion.followBlend(dt: dt)
        var next: [Card] = []
        var unsettled: CGFloat = 0
        let drops: [CGFloat] = [24, 33, 22, 37, 29, 21, 38, 26]
        let tilts: [CGFloat] = [-4, 3, -2, 5, 2, -5, 3, -3]
        // Reserve the permanent card footprint first so history never pushes it around.
        let layoutEntries = entries.enumerated().sorted { $0.element.isPermanent && !$1.element.isPermanent }
        for (slot, entry) in layoutEntries where slot < attachments.count {
            let a = attachments[slot]
            let layoutSlot = entry.isPermanent ? IvoryTreeLayout.pageSize : slot
            let width = entry.isPermanent ? 72.0 : min(IvoryTreeLayout.cardWidth, max(130, bounds.width * 0.32))
            let restingHeight = entry.imageFirst ? IvoryTreeLayout.imageCardHeight : IvoryTreeLayout.cardHeight
            let expandedHeight = entry.imageFirst ? IvoryTreeLayout.selectedImageHeight : IvoryTreeLayout.selectedHeight
            let target = entry.isPermanent ? width * 1.61803398875 : (entry.id == selectedID ? expandedHeight : restingHeight)
            let old = heights[entry.id] ?? target
            let height = reduced ? target : old + (target - old) * blend
            heights[entry.id] = height
            unsettled += abs(target - height)
            var rect = NSRect(
                x: a.point.x - width / 2 + sway * 0.6, y: a.point.y + drops[layoutSlot % 8], width: width,
                height: height)
            rect.origin.x = max(8, min(bounds.width - width - 8, rect.minX))
            // Preserve the branch attachment, lengthening the cord only when two
            // papers overlap in projection (especially near a side-on view).
            for prior in next where rect.insetBy(dx: -6, dy: -6).intersects(prior.rect) {
                rect.origin.y = prior.rect.maxY + 9
            }
            rect.origin.y = max(8, min(bounds.height - height - 8, rect.minY))
            next.append(
                Card(
                    entry: entry, rect: rect, anchor: a.point, tilt: reduced ? 0 : tilts[layoutSlot % 8] + sway,
                    opacity: 1))
        }
        cards = next
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
        selectionFade = min(1, selectionFade + dt / TreeMotion.fadeDuration)
        if !isTurningPage { outgoing.removeAll() }
        isAnimating = isTurningPage || unsettled > 0.05 || selectionFade < 1
        syncIslands()
        needsDisplay = true
    }
    private func visuals() -> [Card] {
        let elapsed = CGFloat(CACurrentMediaTime() - turnStart)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var result: [Card] = []
        if elapsed < TreeMotion.outgoingDuration {
            for var card in outgoing {
                let p = min(1, elapsed / TreeMotion.outgoingDuration)
                card.opacity *= 1 - p
                if !reduced {
                    card.fold *= max(0.02, cos(p * .pi / 2))
                    card.rect.origin.x -= turnDirection * 8 * p
                }
                result.append(card)
            }
        }
        for (slot, var card) in cards.enumerated() {
            if card.entry.isPermanent { result.append(card); continue }
            let p = max(0, min(1, (elapsed - CGFloat(slot) * TreeMotion.pageStagger) / TreeMotion.incomingDuration))
            card.opacity *= reduced ? min(1, elapsed / TreeMotion.fadeDuration) : p
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
                min(1, CGFloat(CACurrentMediaTime() - turnStart) / TreeMotion.incomingDuration) * card.opacity * selectionFade)
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
        (selected
            ? IvoryPaperStyle.fill
            : NSColor(red: 0.79, green: 0.77, blue: 0.71, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.36, alpha: 0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 1.7, y: rect.minY + 5.3, width: 3.4, height: 3.4))
            .fill()
        if card.entry.kind == .phoneSync {
            drawPhone(in: rect)
            return
        }
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
        if selected && !card.entry.date.isEmpty { body.size.height -= 15 }
        if card.entry.imageFirst {
            // The photograph owns the paper body. OCR is reserved for preview.
            if let image = images[card.entry.id] {
                drawImage(image, in: body)
            } else if let placeholder = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
                drawImage(placeholder, in: NSRect(x: body.midX - 13, y: body.midY - 13, width: 26, height: 26))
            }
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            (String(card.entry.title.prefix(500)) as NSString).draw(
                with: body, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: IvoryPaperStyle.ink,
                    .paragraphStyle: paragraph,
                ])
        }
        if selected && !card.entry.date.isEmpty {
            (card.entry.date as NSString).draw(
                in: NSRect(x: rect.minX + 10, y: rect.maxY - 19, width: rect.width - 20, height: 14),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.36, alpha: 1),
                ])
        }
    }
    private func drawPhone(in rect: NSRect) {
        let phone = NSRect(x: rect.midX - 19, y: rect.minY + 16, width: 38, height: 60)
        IvoryPaperStyle.ink.setStroke()
        let outline = NSBezierPath(roundedRect: phone, xRadius: 5, yRadius: 5)
        outline.lineWidth = 1.5
        outline.stroke()
        if let qr = NSImage(systemSymbolName: "qrcode", accessibilityDescription: nil) {
            drawImage(qr, in: NSRect(x: phone.minX + 5, y: phone.minY + 15, width: 28, height: 28))
        }
        NSBezierPath(roundedRect: NSRect(x: phone.midX - 6, y: phone.minY + 5, width: 12, height: 1.5), xRadius: 1, yRadius: 1).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (L10n.phoneSync as NSString).draw(in: NSRect(x: rect.minX + 4, y: rect.maxY - 21, width: rect.width - 8, height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: IvoryPaperStyle.ink, .paragraphStyle: paragraph])
    }

    private func drawImage(_ image: NSImage, in bounds: NSRect) {
        let ratio = min(bounds.width / max(1, image.size.width), bounds.height / max(1, image.size.height))
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    func entryID(at point: NSPoint) -> UUID? {
        // Do not let a click on a departing title activate the incoming record.
        // Keyboard selection/paste still takes effect immediately through the model.
        guard CACurrentMediaTime() - turnStart >= Double(TreeMotion.outgoingDuration) else { return nil }
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
            item.action = { [weak self] in self?.onPreview?(entry.id) }
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
    var draggable = true
    var paint: (() -> Void)?
    private var visual: PaperFlightView?
    func present(image: NSImage, pose: PaperPose, canvas: NSRect, color: NSColor, opacity: CGFloat) {
        let view: PaperFlightView
        if let visual { view = visual }
        else {
            view = PaperFlightView(frame: bounds)
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            visual = view
        }
        view.compactImage = image
        view.compactColor = color
        view.expansion = 0
        view.alphaValue = opacity
        view.place(pose, canvas: canvas)
    }
    var onSelect: (() -> Void)?
    var onPreview: (() -> Void)?
    var enabled = true { didSet { setAccessibilityEnabled(enabled) } }
    private var dragPayload: (() -> [NSPasteboardWriting]?)?
    private var downEvent: NSEvent?
    private var dragOwner: HistoryPanel?
    private var down = NSPoint.zero
    private var dragged = false
    private var previewAtDown: (() -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) { if visual == nil { paint?() } }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }; onPreview?(); return true
    }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        guard let owner = (window as? TreeInteractionPanel)?.owner, !owner.layoutEditing else { return }
        downEvent = event
        dragPayload = recordID.flatMap { owner.prepareDrag?($0) }
        down = event.locationInWindow
        dragged = false
        previewAtDown = onPreview
        (window as? TreeInteractionPanel)?.owner?.focusSearch()
    }
    override func mouseDragged(with event: NSEvent) {
        guard draggable, enabled, window?.isVisible == true, !dragged, let downEvent,
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
        if let visual { return visual.faceImage() }
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
        downEvent = nil; dragPayload = nil; previewAtDown = nil
        owner?.finishPaperDrag(operation: operation)
    }
    override func mouseUp(with event: NSEvent) {
        defer { previewAtDown = nil; downEvent = nil; dragPayload = nil }
        guard enabled, window?.isVisible == true, !dragged, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        previewAtDown?()
    }
}
