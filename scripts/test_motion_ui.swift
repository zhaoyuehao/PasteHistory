import AppKit
import QuartzCore

/// Opt-in native smoke test. Uses fixture windows, never the user's history.
@main
struct PaperMotionSmoke {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        checkPaperMotion()
        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let compact = PaperPose(pin: NSPoint(x: 620.35, y: 540.65), size: NSSize(width: 158, height: 112), angle: 0.06, padding: 3)
        let reading = PaperPose(pin: compact.pin, size: NSSize(width: 480, height: 297))
        func image(_ size: NSSize) -> NSImage {
            let result = NSImage(size: size)
            result.lockFocus()
            IvoryPaperStyle.fill.setFill(); NSRect(origin: .zero, size: size).fill()
            ("纸面 Motion — 123" as NSString).draw(at: NSPoint(x: 12,y: size.height-40),
                withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
            NSColor.blue.setFill(); NSBezierPath(ovalIn: NSRect(x: 15,y: 15,width: 30,height: 30)).fill()
            result.unlockFocus()
            return result
        }
        let small = image(compact.size), large = image(reading.size)
        let flight = PaperPreviewFlight()
        var samples: [PaperPreviewFlight.FrameSample] = []
        flight.observeFrame = { samples.append($0) }
        var completions = 0
        let id = UUID()
        func animate(_ opening: Bool) {
            flight.animate(from: opening ? compact : reading, to: opening ? reading : compact,
                readingImage: large, compactImage: small, recordID: id,
                opening: opening) { completions += 1 }
        }
        animate(true)
        let panel = NSApp.windows.first { $0.isVisible && $0.title == "纸签预览过渡" } as! PaperPreviewPanel
        precondition(!panel.canBecomeKey)
        var pinches = 0
        flight.onMagnify = { _, _ in pinches += 1; return true }
        precondition(panel.routeMagnification(from: panel, at: NSPoint(x: 20,y: 20), delta: 0.1, phase: .began))
        precondition(!panel.routeMagnification(from: nil, at: NSPoint(x: 20,y: 20), delta: 0.1, phase: .began))
        precondition(!panel.routeMagnification(from: panel, at: NSPoint(x: -1,y: 20), delta: 0.1, phase: .began))
        precondition(pinches == 1, "Only the moving paper may consume the gesture, once")
        for index in 0..<8 {
            run(0.055)
            let before = flight.visiblePose!.channels
            animate(index.isMultiple(of: 2) ? false : true)
            precondition(flight.visiblePose!.channels == before, "Retarget must preserve the presented frame")
        }
        let deadline = Date().addingTimeInterval(1.2)
        while flight.visiblePose != nil && Date() < deadline { run(0.01) }
        precondition(flight.visiblePose == nil && completions == 1,
                     "Only the latest request may complete, within the settling bound")
        precondition(!panel.handlesPaperPinch, "A hidden flight must remove its input monitor")
        precondition(samples.count > 15)
        for sample in samples {
            precondition(sample.windowFrame.width <= sample.pose.frame.width+2 && sample.windowFrame.height <= sample.pose.frame.height+2,
                         "The animation window must stay bounded to the paper")
        }
        // A completion may immediately open a new animation. The old completion
        // must not hide the reused window or cancel its display clock.
        flight.animate(from: reading, to: compact, readingImage: large, compactImage: small,
                       recordID: id, opening: false) { animate(true) }
        run(0.65)
        precondition(flight.visiblePose != nil && panel.isVisible)
        run(0.7)
        precondition(flight.visiblePose == nil && completions == 2)
        let csv = "delta_ms,callback_ms,width,expansion,finished\n" + samples.map {
            "\($0.delta*1000),\($0.work*1000),\($0.pose.size.width),\($0.expansion),\($0.finished)"
        }.joined(separator: "\n")
        try csv.write(toFile: ".build/paper-motion-frames.csv", atomically: true, encoding: .utf8)
        let work = samples.map(\.work).sorted()
        print("Native callbacks: \(samples.count); p95 work \(work[Int(Double(work.count-1)*0.95)]*1000) ms; max \(work.last!*1000) ms. These are callback costs, not compositor frame times.")
        print("PASS: rapid reversal, latest completion, reentrant reopen, scoped flight gestures, bounded windows")
        flight.cancel()
        let reduced = PaperPreviewFlight(reduceMotion: { true })
        var reducedDone = false
        reduced.animate(from: compact, to: reading, readingImage: large, compactImage: small,
                        opening: true) { reducedDone = true }
        precondition(reduced.visiblePose?.channels == reading.channels)
        run(0.05)
        precondition(reduced.visiblePose?.channels == reading.channels && !reducedDone)
        run(0.15)
        precondition(reducedDone && reduced.visiblePose == nil)
        reduced.cancel()
        print("PASS: Reduce Motion keeps geometry fixed and finishes its short fade")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("motion-ui-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        Settings.shared.iCloudSync = false
        let store = ClipStore(directory: directory)
        let entry = ClipItem(kind: .text, text: "Continuous paper\n纸面交接检查：中文 English 123\nA single physical sheet.", sourceApp: "Motion fixture")
        store.syncDatabase.upsert(entry); store.refresh()
        let pairing = PairModel(readConnection: { ("", "") }, startService: {}, renewCode: {})
        let controller = PanelController(store: store, observesDesktopFocus: false, pairing: pairing)
        func settle() {
            let deadline = Date().addingTimeInterval(1.2)
            repeat { run(0.01) } while NSApp.windows.contains { $0.isVisible && $0.title == "纸签预览过渡" } && Date() < deadline
            precondition(!NSApp.windows.contains { $0.isVisible && $0.title == "纸签预览过渡" })
        }
        func bitmap(_ image: NSImage) -> NSBitmapImageRep { NSBitmapImageRep(data: image.tiffRepresentation!)! }
        func save(_ rep: NSBitmapImageRep, _ name: String) throws {
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/"+name+".png"))
        }
        func compare(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, limit: Double, context: String) {
            precondition(a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh, context)
            var difference = 0.0
            for y in 0..<a.pixelsHigh { for x in 0..<a.pixelsWide {
                let ca = a.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                let cb = b.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                difference += abs(ca.redComponent-cb.redComponent)+abs(ca.greenComponent-cb.greenComponent)+abs(ca.blueComponent-cb.blueComponent)
            } }
            let mean = difference/Double(a.pixelsWide*a.pixelsHigh*3)
            print("\(context): mean RGB error \(mean)")
            precondition(mean < limit, context)
        }
        controller.show(); run(0.9)
        let source = controller.previewPaper!.contentView as! TreePaperSurface
        let sourcePixels = bitmap(source.paperImage())
        controller.togglePreview()
        let moving = NSApp.windows.first { $0.isVisible && $0.title == "纸签预览过渡" }!
        let movingFace = moving.contentView as! PaperFlightView
        let firstPixels = bitmap(movingFace.faceImage())
        try save(sourcePixels, "motion-source"); try save(firstPixels, "motion-first-flight")
        compare(sourcePixels, firstPixels, limit: 0.001, context: "Compact-to-flight handoff")
        // Magnification during travel must change this same paper's destination.
        let movingPanel = moving as! PaperPreviewPanel
        precondition(movingPanel.routeMagnification(from: movingPanel, at: NSPoint(x: 30,y: 30), delta: 0.2, phase: .began))
        _ = movingPanel.routeMagnification(from: movingPanel, at: NSPoint(x: 30,y: 30), delta: 0, phase: .ended)
        settle()
        let live = NSApp.windows.first { $0.isVisible && $0.title == L10n.previewTitle }!
        precondition(live.alphaValue == 1 && live.frame.width > PreviewPanelController.paperSize(for: entry).width*1.15)
        let liveView = live.contentView!
        let livePixels = liveView.bitmapImageRepForCachingDisplay(in: liveView.bounds)!
        liveView.cacheDisplay(in: liveView.bounds, to: livePixels)
        // Compare at the physical size because the live document has logical bounds.
        let liveImage = NSImage(size: live.frame.size); liveImage.addRepresentation(livePixels)
        controller.togglePreview()
        let closingFace = moving.contentView as! PaperFlightView
        try save(bitmap(liveImage), "motion-live"); try save(bitmap(closingFace.faceImage()), "motion-close-start")
        compare(bitmap(liveImage), bitmap(closingFace.faceImage()), limit: 0.005, context: "Magnified live-to-flight handoff")
        settle()
        precondition(controller.previewPaper?.alphaValue == 1)
        controller.hide(restoreFocus: false); run(0.25)
        print("PASS: actual tree source handoff, magnify during flight, close restores source")
    }
}
