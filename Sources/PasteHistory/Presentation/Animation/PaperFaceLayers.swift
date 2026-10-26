import AppKit
import QuartzCore

/// Shared by a hanging paper and its flight. Images are uploaded only when their
/// content changes; frames update transforms/masks, never redraw text or images.
final class PaperFaceLayers {
    let root = CALayer()
    private let paper = CALayer()
    private let compact = CALayer()
    private let reading = CALayer()
    private let compactMask = CAShapeLayer()
    private let readingMask = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let hole = CAShapeLayer()
    private var compactImage: NSImage?
    private var readingImage: NSImage?

    init() {
        root.addSublayer(paper)
        paper.addSublayer(compact); paper.addSublayer(reading)
        paper.addSublayer(edge); paper.addSublayer(hole)
        paper.masksToBounds = true
        compact.mask = compactMask; reading.mask = readingMask
        edge.fillColor = nil
        edge.strokeColor = IvoryPaperStyle.edge.cgColor
        hole.fillColor = IvoryPaperStyle.meta.withAlphaComponent(0.7).cgColor
    }
    func images(compact nextCompact: NSImage?, reading nextReading: NSImage?) {
        if compactImage !== nextCompact {
            compactImage = nextCompact
            compact.contents = nextCompact?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        if readingImage !== nextReading {
            readingImage = nextReading
            reading.contents = nextReading?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
    func place(_ pose: PaperPose, canvas: NSRect, expansion: CGFloat,
               compactColor: NSColor = IvoryPaperStyle.fill, backingScale: CGFloat = 2) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.frame = NSRect(origin: .zero, size: canvas.size)
        let size = pose.size
        paper.bounds = NSRect(origin: .zero, size: size)
        paper.anchorPoint = CGPoint(x: 0.5, y: 1-pose.inset/size.height)
        paper.position = CGPoint(x: pose.pin.x-canvas.minX, y: pose.pin.y-canvas.minY)
        paper.setAffineTransform(CGAffineTransform(rotationAngle: pose.angle))
        let scale = pose.inset/IvoryPaperStyle.pinInset
        paper.cornerRadius = IvoryPaperStyle.radius*scale
        let t = min(1, max(0, expansion))
        let blend = readingImage == nil && compactImage == nil ? t
            : readingImage == nil ? CGFloat(0) : compactImage == nil ? 1 : Self.blend(t)
        paper.backgroundColor = (compactColor.blended(withFraction: blend, of: IvoryPaperStyle.fill) ?? IvoryPaperStyle.fill).cgColor
        func placeFace(_ layer: CALayer, mask: CAShapeLayer, image: NSImage?, opacity: CGFloat) {
            guard let image else { layer.isHidden = true; return }
            layer.isHidden = false
            let fit = min(size.width/max(1,image.size.width), size.height/max(1,image.size.height))
            layer.bounds = NSRect(origin: .zero, size: image.size)
            layer.anchorPoint = CGPoint(x: 0.5, y: 1-IvoryPaperStyle.pinInset/image.size.height)
            layer.position = CGPoint(x: size.width/2, y: size.height-pose.inset)
            layer.setAffineTransform(CGAffineTransform(scaleX: fit, y: fit))
            layer.opacity = Float(opacity)
            layer.contentsScale = backingScale
            // The shared shell owns the edge and suspension hole in every mode.
            mask.path = CGPath(rect: NSRect(x: 2, y: 2, width: max(0,image.size.width-4),
                                           height: max(0,image.size.height-12)), transform: nil)
        }
        placeFace(compact, mask: compactMask, image: compactImage, opacity: 1-blend)
        placeFace(reading, mask: readingMask, image: readingImage, opacity: blend)
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
    private static func blend(_ t: CGFloat) -> CGFloat {
        let u = min(1, max(0, (t-0.15)/0.7))
        return u*u*(3-2*u)
    }
}
