import AppKit

/// Rendering and native-window behavior. Numeric integration is checked separately
/// by test_damped_motion.swift, without depending on the display refresh rate.
@MainActor
func checkPaperMotion() {
    let image = NSImage(size: NSSize(width: 480, height: 297))
    image.lockFocus()
    IvoryPaperStyle.fill.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    NSColor.blue.setFill()
    NSBezierPath(ovalIn: NSRect(x: 40, y: 212, width: 60, height: 60)).fill()
    image.unlockFocus()
    for size in [NSSize(width: 180, height: 120), NSSize(width: 300, height: 210), image.size] {
        let view = PaperFlightView(frame: NSRect(origin: .zero, size: size))
        view.pose = PaperPose(frame: view.bounds)
        view.compactImage = image
        let bitmap = NSBitmapImageRep(data: view.faceImage().tiffRepresentation!)!
        var left = bitmap.pixelsWide, right = -1, top = bitmap.pixelsHigh, bottom = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.blueComponent > 0.8 && color.redComponent < 0.2 else { continue }
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        precondition(right > left && abs((right-left)-(bottom-top)) <= 2,
                     "A circular image feature must stay circular while the paper changes aspect ratio")
        let pixelScale = CGFloat(bitmap.pixelsWide) / size.width
        precondition(abs(CGFloat(right-left+1) / pixelScale - 60 * min(size.width/image.size.width, size.height/image.size.height)) < 2,
                     "Content must scale uniformly with the paper instead of being cropped at its original size")
    }
    let compact = PaperPose(pin: NSPoint(x: 600, y: 500), size: NSSize(width: 158, height: 112), angle: 0.06, padding: 3)
    let reading = PaperPose(pin: NSPoint(x: 604, y: 495), size: image.size)
    let compactImage = NSImage(size: compact.size)
    compactImage.lockFocus()
    IvoryPaperStyle.fill.setFill(); NSRect(origin: .zero, size: compact.size).fill()
    NSColor.red.setFill(); NSRect(x: 20, y: 25, width: 80, height: 45).fill()
    compactImage.unlockFocus()
    // The motion driver borrows a visible card; it never owns window visibility.
    let original = NSPanel(contentRect: reading.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    original.isReleasedWhenClosed = false
    let originalFace = PaperFlightView(frame: NSRect(origin: .zero, size: reading.size))
    original.contentView = originalFace
    originalFace.compactImage = compactImage
    originalFace.expansion = 1
    originalFace.place(reading, in: original)
    original.orderFrontRegardless()
    let flight = PaperPreviewFlight()
    flight.bind(window: original, sheet: originalFace)
    flight.animate(to: compact, opening: false, completion: {})
    precondition(original.isVisible && original.alphaValue == 1)
    precondition(flight.visiblePose?.channels == reading.channels)
    flight.cancel()
    precondition(original.isVisible && original.contentView === originalFace)
    original.orderOut(nil)

    // Render into a real native window: integer window placement must not move
    // the fractional screen-space hanging hole as the sheet grows and straightens.
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    let face = PaperFlightView(frame: .zero)
    panel.contentView = face
    let pin = NSPoint(x: 600.35, y: 500.65)
    for index in 0..<24 {
        let t = CGFloat(index) / 23
        let pose = PaperPose(pin: pin, size: NSSize(width: 158 + 182*t, height: 112 + 98*t), angle: 0.06*(1-t))
        face.place(pose, in: panel)
        face.layoutSubtreeIfNeeded()
        let rep = face.bitmapImageRepForCachingDisplay(in: face.bounds)!
        face.cacheDisplay(in: face.bounds, to: rep)
        let sx = CGFloat(rep.pixelsWide) / face.bounds.width
        let sy = CGFloat(rep.pixelsHigh) / face.bounds.height
        let local = NSPoint(x: pin.x-panel.frame.minX, y: pin.y-panel.frame.minY)
        let expectedX = local.x*sx, expectedY = (face.bounds.height-local.y)*sy
        var weight: CGFloat = 0, sumX: CGFloat = 0, sumY: CGFloat = 0
        for y in Int(expectedY-3*sy)...Int(expectedY+3*sy) {
            for x in Int(expectedX-3*sx)...Int(expectedX+3*sx) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      c.alphaComponent > 0.9 else { continue }
                let ink = max(0, 0.8-c.redComponent)
                weight += ink; sumX += (CGFloat(x)+0.5)*ink; sumY += (CGFloat(y)+0.5)*ink
            }
        }
        precondition(weight > 0)
        let measured = NSPoint(x: panel.frame.minX + sumX/weight/sx,
                              y: panel.frame.minY + face.bounds.height - sumY/weight/sy)
        precondition(hypot(measured.x-pin.x, measured.y-pin.y) < 0.45,
                     "The rendered pin must stay fixed despite native window rounding: \(measured) vs \(pin)")
    }
    panel.orderOut(nil)

    print("PASS: uniform face scaling, persistent window ownership, subpixel pin stability")
}
