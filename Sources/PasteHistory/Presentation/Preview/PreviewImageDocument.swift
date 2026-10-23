import AppKit
import SwiftUI

/// One native scroll document: a full viewport of image, then selectable OCR.
/// No nested scroll views compete for two-finger scrolling or magnification.
struct PreviewImageDocument: NSViewRepresentable {
    let image: NSImage?
    let details: String
    let identity: UUID
    let paperStyle: Bool

    func makeNSView(context: Context) -> PreviewImageScrollView { PreviewImageScrollView() }
    func updateNSView(_ scroll: PreviewImageScrollView, context: Context) {
        scroll.update(image: image, details: details, identity: identity, paperStyle: paperStyle)
    }
}

final class PreviewImageScrollView: PreviewZoomScrollView {
    let sheet = PreviewImageSheet()
    private var identity: UUID?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        documentView = sheet
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(image: NSImage?, details: String, identity: UUID, paperStyle: Bool) {
        let changed = self.identity != identity
        self.identity = identity
        sheet.update(image: image, details: details, paperStyle: paperStyle)
        if changed { resetViewport() }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        // Layout is measured in unzoomed points; pinch scales the document,
        // rather than reflowing OCR or shrinking the image beneath the fingers.
        sheet.arrange(viewport: contentSize)
    }
}

final class PreviewImageSheet: NSView {
    let picture = NSImageView()
    let recognizedText = NSTextView()
    private var viewport = NSSize.zero
    private var layoutDirty = true
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.setAccessibilityLabel(L10n.image)
        addSubview(picture)
        recognizedText.isEditable = false
        recognizedText.isSelectable = true
        recognizedText.drawsBackground = false
        recognizedText.font = .systemFont(ofSize: Scale.body)
        recognizedText.textContainerInset = NSSize(width: 21, height: 13)
        recognizedText.textContainer?.lineFragmentPadding = 0
        recognizedText.textContainer?.widthTracksTextView = true
        addSubview(recognizedText)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(image: NSImage?, details: String, paperStyle: Bool) {
        picture.image = image ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        if recognizedText.string != details {
            recognizedText.string = details
            layoutDirty = true
        }
        recognizedText.textColor = paperStyle ? IvoryPaperStyle.ink : .labelColor
    }
    func arrange(viewport: NSSize) {
        guard viewport.width > 0, viewport.height > 0, layoutDirty || self.viewport != viewport else { return }
        self.viewport = viewport
        layoutDirty = false
        picture.frame = NSRect(origin: .zero, size: viewport).insetBy(dx: 13, dy: 13)
        let hasDetails = !recognizedText.string.isEmpty
        recognizedText.isHidden = !hasDetails
        var detailHeight: CGFloat = 0
        if hasDetails {
            recognizedText.frame = NSRect(x: 0, y: viewport.height + 8, width: viewport.width, height: 1)
            recognizedText.textContainer?.containerSize = NSSize(width: max(1, viewport.width - 42), height: .greatestFiniteMagnitude)
            if let layout = recognizedText.layoutManager, let container = recognizedText.textContainer {
                layout.ensureLayout(for: container)
                detailHeight = max(44, ceil(layout.usedRect(for: container).height) + 26)
            }
            recognizedText.setFrameSize(NSSize(width: viewport.width, height: detailHeight))
        }
        setFrameSize(NSSize(width: viewport.width, height: viewport.height + (hasDetails ? detailHeight + 21 : 0)))
    }
}
