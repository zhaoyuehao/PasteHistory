import AppKit
import QuartzCore

/// A persistent shell and a cached compact face. The live reading document is
/// a sibling NSView; it never becomes a bitmap or owns the paper's chrome.
final class PaperFaceLayers {
    let root = CALayer()
    private let paper = CALayer()
    private let compact = CALayer()
    private let compactMask = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let hole = CAShapeLayer()
    private var compactImage: NSImage?

    init() {
        root.addSublayer(paper)
        paper.addSublayer(compact)
        paper.addSublayer(edge)
        paper.addSublayer(hole)
        paper.masksToBounds = true
        compact.mask = compactMask
        edge.fillColor = nil
        edge.strokeColor = IvoryPaperStyle.edge.cgColor
        hole.fillColor = IvoryPaperStyle.meta.withAlphaComponent(0.7).cgColor
    }
    func image(_ image: NSImage?) {
        guard compactImage !== image else { return }
        compactImage = image
        let pixels = Self.pixels(image)
        compact.contents = pixels
        compact.contentsScale = CGFloat(pixels?.width ?? 1) / max(1, image?.size.width ?? 1)
    }
    func place(_ pose: PaperPose, canvas: NSRect, expansion: CGFloat,
               compactColor: NSColor = IvoryPaperStyle.fill, backingScale: CGFloat = 2,
               liveReading: Bool = false) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.frame = NSRect(origin: .zero, size: canvas.size)
        let size = pose.size
        paper.bounds = NSRect(origin: .zero, size: size)
        paper.anchorPoint = CGPoint(x: 0.5, y: 1-pose.inset/size.height)
        paper.position = CGPoint(x: pose.pin.x-canvas.minX, y: pose.pin.y-canvas.minY)
        paper.setAffineTransform(CGAffineTransform(rotationAngle: pose.angle))
        let scale = pose.inset/IvoryPaperStyle.pinInset
        paper.cornerRadius = IvoryPaperStyle.radius*scale
        let blend = liveReading ? Self.blend(expansion) : 0
        paper.backgroundColor = (compactColor.blended(withFraction: blend, of: IvoryPaperStyle.fill)
            ?? IvoryPaperStyle.fill).cgColor
        compact.isHidden = compactImage == nil
        if let image = compactImage {
            // Keep text at one logical scale while the card's animated height
            // changes. The paper layer clips the stable face instead of
            // repeatedly scaling/rasterizing glyphs during selection and paging.
            let fit = size.width/max(1,image.size.width)
            compact.bounds = NSRect(origin: .zero, size: image.size)
            compact.anchorPoint = CGPoint(x: 0.5, y: 1-IvoryPaperStyle.pinInset/image.size.height)
            compact.position = CGPoint(x: size.width/2, y: size.height-pose.inset)
            compact.setAffineTransform(CGAffineTransform(scaleX: fit, y: fit))
            compact.opacity = Float(1-blend)
            compactMask.path = CGPath(rect: NSRect(x: 2, y: 2, width: max(0,image.size.width-4),
                height: max(0,image.size.height-12)), transform: nil)
        }
        edge.frame = paper.bounds
        edge.path = CGPath(roundedRect: paper.bounds.insetBy(dx: 0.75*scale, dy: 0.75*scale),
                           cornerWidth: 3.25*scale, cornerHeight: 3.25*scale, transform: nil)
        edge.lineWidth = 1.5*scale
        edge.opacity = Float(blend)
        hole.frame = paper.bounds
        let radius = 1.7*scale
        hole.path = CGPath(ellipseIn: NSRect(x: size.width/2-radius, y: size.height-pose.inset-radius,
                                           width: radius*2, height: radius*2), transform: nil)
        edge.contentsScale = backingScale; hole.contentsScale = backingScale
        CATransaction.commit()
    }
    private static func pixels(_ image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide < $1.pixelsWide }) { return bitmap.cgImage }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    static func blend(_ t: CGFloat) -> CGFloat {
        // Keep the compact face during the initial travel, then reveal the live
        // document through the remaining expansion instead of finishing at 85%.
        let u = min(1, max(0, (t-Motion.paperContentRevealStart)/(1-Motion.paperContentRevealStart)))
        return u*u*(3-2*u)
    }
}
