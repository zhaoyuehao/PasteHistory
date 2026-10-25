import AppKit

/// Behavior checks for the shared trajectory and actual rendered paper face.
@MainActor
func checkPaperMotion() {
    let track = SettlingTrack(start: 158, end: 480, duration: 0.2, symmetric: true)
    var previous: CGFloat = 158
    for index in 0...200 {
        let sample = track.sample(Double(index) / 1000)
        precondition(sample.value >= previous && sample.value <= 480)
        previous = sample.value
    }
    for instant in [0.025, 0.06, 0.12, 0.19] {
        let moving = track.sample(instant)
        let reverse = SettlingTrack(start: moving.value, end: 158,
                                    velocity: moving.velocity, duration: 0.16, symmetric: true)
        precondition(abs(reverse.sample(0).value-moving.value) < 0.0001)
        let measuredVelocity = (reverse.sample(0.000001).value-reverse.sample(0).value) / 0.000001
        precondition(abs(measuredVelocity-moving.velocity) < 0.2,
                     "Reversing a moving sheet must retain its incoming velocity")
        precondition(abs(reverse.sample(0.16).value-158) < 0.0001 && reverse.sample(0.16).velocity == 0)
    }

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
        view.readingImage = image
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
    // With unchanged endpoints/content, the closing frame at T-t must equal
    // the opening frame at t, including text handoff, tilt and image proportions.
    let compact = PaperPose(pin: NSPoint(x: 600, y: 500), size: NSSize(width: 158, height: 112), angle: 0.06, padding: 3)
    let reading = PaperPose(pin: NSPoint(x: 604, y: 495), size: image.size)
    let compactImage = NSImage(size: compact.size)
    compactImage.lockFocus()
    IvoryPaperStyle.fill.setFill(); NSRect(origin: .zero, size: compact.size).fill()
    NSColor.red.setFill(); NSRect(x: 20, y: 25, width: 80, height: 45).fill()
    compactImage.unlockFocus()
    let forwards = zip(compact.channels+[0], reading.channels+[1]).map {
        SettlingTrack(start: $0.0, end: $0.1, duration: Motion.paperOpenDuration, symmetric: true)
    }
    let backwards = zip(reading.channels+[1], compact.channels+[0]).map {
        SettlingTrack(start: $0.0, end: $0.1, duration: Motion.paperCloseDuration, symmetric: true)
    }
    for fraction in [0.0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0] {
        let a = forwards.map { $0.sample(fraction*Motion.paperOpenDuration).value }
        let b = backwards.map { $0.sample((1-fraction)*Motion.paperCloseDuration).value }
        precondition(zip(a,b).allSatisfy { abs($0-$1) < 0.000001 }, "Opening and closing must retrace the same geometry and content phase")
        let frames = [a,b].map { channels -> NSBitmapImageRep in
            let face = PaperFlightView(frame: .zero)
            face.pose = PaperPose(channels: Array(channels.prefix(7)))
            face.expansion = channels[7]
            face.compactImage = compactImage; face.readingImage = image
            return NSBitmapImageRep(data: face.faceImage().tiffRepresentation!)!
        }
        precondition(frames[0].pixelsWide == frames[1].pixelsWide && frames[0].pixelsHigh == frames[1].pixelsHigh)
        let count = frames[0].bytesPerRow*frames[0].pixelsHigh
        let left = UnsafeBufferPointer(start: frames[0].bitmapData!, count: count)
        let right = UnsafeBufferPointer(start: frames[1].bitmapData!, count: count)
        precondition(zip(left,right).filter { abs(Int($0)-Int($1)) > 2 }.count < max(1,count/1000),
                     "Reverse playback must render the same paper, not a separate dismissal effect")
    }
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

    // A narrow letter-like stem stays upright while only the shell straightens.
    let textFace = NSImage(size: image.size)
    textFace.lockFocus()
    IvoryPaperStyle.fill.setFill(); NSRect(origin: .zero, size: textFace.size).fill()
    NSColor.blue.setFill(); NSRect(x: 30, y: 217, width: 4, height: 30).fill()
    textFace.unlockFocus()
    for angle in [CGFloat(-0.08), -0.04, 0, 0.04, 0.08] {
        let view = PaperFlightView(frame: .zero)
        view.pose = PaperPose(pin: .zero, size: NSSize(width: 240, height: 170), angle: angle)
        view.readingImage = textFace
        let rep = NSBitmapImageRep(data: view.faceImage().tiffRepresentation!)!
        var left = rep.pixelsWide, right = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      c.blueComponent > 0.8 && c.redComponent < 0.2 else { continue }
                left = min(left, x); right = max(right, x)
            }
        }
        let scale = CGFloat(rep.pixelsWide)/view.pose.frame.width
        precondition(right > left && CGFloat(right-left+1)/scale < 5,
                     "Reading glyphs must not rotate or blur with the straightening shell")
    }
    print("PASS: monotone settle, interruption velocity, exact endpoints, symmetric forward/reverse pixels, undistorted rendered image, subpixel pin stability, upright reading face")
}
