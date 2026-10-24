import AppKit

/// Behavior checks for the shared trajectory and actual rendered paper face.
@MainActor
func checkPaperMotion() {
    let track = SettlingTrack(start: 158, end: 480, duration: 0.2)
    var previous: CGFloat = 158
    for index in 0...200 {
        let sample = track.sample(Double(index) / 1000)
        precondition(sample.value >= previous && sample.value <= 480)
        previous = sample.value
    }
    for instant in [0.025, 0.06, 0.12, 0.19] {
        let moving = track.sample(instant)
        let reverse = SettlingTrack(start: moving.value, end: 158,
                                    velocity: moving.velocity, duration: 0.16)
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
        view.source = image
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
        precondition(abs(CGFloat(right-left+1) / pixelScale - 60) < 2,
                     "Content must keep its reading scale while the paper exposes more of it")
    }
    print("PASS: monotone settle, interruption velocity, exact endpoints, undistorted rendered image")
}
