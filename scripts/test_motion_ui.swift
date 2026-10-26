import AppKit
import QuartzCore
import SwiftUI

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
        let small = image(compact.size)
        let panel = PaperPreviewPanel(contentRect: compact.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.acceptsKeyboardFocus = false
        let face = PaperFlightView(frame: NSRect(origin: .zero, size: compact.frame.size))
        face.autoresizingMask = [.width, .height]
        face.compactImage = small
        face.expansion = 0
        panel.contentView = face
        face.place(compact, in: panel)
        let document = NSHostingView(rootView: Text("Live document — 同一内容视图"))
        let readingSurface = PaperPreviewSurface(document: document)
        readingSurface.readingSize = reading.size
        face.attachReading(readingSurface)
        panel.orderFrontRegardless()
        panel.beginPaperInteraction()
        let flight = PaperPreviewFlight()
        flight.bind(window: panel, sheet: face)
        var samples: [PaperPreviewFlight.FrameSample] = []
        var readingEnabledBeforeSettling = false
        flight.observeFrame = {
            samples.append($0)
            if face.acceptsReadingInput && !$0.finished {
                readingEnabledBeforeSettling = true
                precondition(panel.canBecomeKey && !panel.isKeyWindow,
                    "Early reading eligibility must not take focus from the current window")
            }
            precondition(panel.alphaValue == 1 && panel.contentView === face)
            precondition(face.readingSurface?.document === document)
            // Native coordinate conversion, not a second hand-written transform,
            // must keep the document's logical pin on the physical hanging point.
            let localPin = readingSurface.convert(NSPoint(x: reading.size.width / 2,
                y: reading.size.height - IvoryPaperStyle.pinInset), to: nil)
            let pin = panel.convertPoint(toScreen: localPin)
            precondition(hypot(pin.x-$0.pose.pin.x, pin.y-$0.pose.pin.y) < 0.01)
        }
        var completions = 0
        func animate(_ opening: Bool) {
            flight.animate(to: opening ? reading : compact, opening: opening) { completions += 1 }
        }
        animate(true)
        precondition(!panel.canBecomeKey)
        var pinches = 0
        panel.onMagnify = { _, _ in pinches += 1; return true }
        precondition(panel.routeMagnification(from: panel, at: NSPoint(x: 20,y: 20), delta: 0.1, phase: .began))
        precondition(!panel.routeMagnification(from: nil, at: NSPoint(x: 20,y: 20), delta: 0.1, phase: .began))
        precondition(!panel.routeMagnification(from: panel, at: NSPoint(x: -1,y: 20), delta: 0.1, phase: .began))
        precondition(pinches == 1)
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
        precondition(panel.handlesPaperPinch && panel.isVisible, "The same paper remains interactive after settling")
        precondition(samples.count > 15)
        precondition(readingEnabledBeforeSettling, "Reading must be available before the motion tail completes")
        for sample in samples {
            precondition(sample.windowFrame.width <= sample.pose.frame.width+2 && sample.windowFrame.height <= sample.pose.frame.height+2,
                         "The animation window must stay bounded to the paper")
        }
        // A completion may immediately open a new animation. The old completion
        // must not hide the reused window or cancel its display clock.
        flight.animate(to: compact, opening: false) { animate(true) }
        precondition(!face.acceptsReadingInput && !panel.canBecomeKey,
            "Closing must revoke reading input immediately, including during reversal")
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
        face.expansion = 0
        face.place(compact, in: panel)
        reduced.bind(window: panel, sheet: face)
        reduced.animate(to: reading, opening: true) { reducedDone = true }
        precondition(reduced.visiblePose?.channels == reading.channels)
        run(0.05)
        precondition(reduced.visiblePose?.channels == reading.channels && !reducedDone)
        run(0.15)
        precondition(reducedDone && reduced.visiblePose == nil)
        reduced.cancel()
        panel.endPaperInteraction()
        panel.orderOut(nil)
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
            while controller.isPreviewAnimating && Date() < deadline { run(0.01) }
            precondition(!controller.isPreviewAnimating)
        }
        controller.show(); run(0.9)
        let source = controller.previewPaper!
        let sourceSurface = source.contentView as! TreePaperSurface
        let sourceRenderer = sourceSurface.visual!
        let windowNumber = source.windowNumber
        controller.togglePreview()
        precondition(controller.previewWindow === source && source.windowNumber == windowNumber)
        precondition(sourceSurface.visual === sourceRenderer)
        let liveDocument = sourceRenderer.readingSurface!.document
        precondition(source.routeMagnification(from: source, at: NSPoint(x: 30,y: 30), delta: 0.2, phase: .began))
        _ = source.routeMagnification(from: source, at: NSPoint(x: 30,y: 30), delta: 0, phase: .ended)
        settle()
        precondition(source.alphaValue == 1 && source.frame.width > PreviewPanelController.paperSize(for: entry).width*1.15)
        precondition(sourceRenderer.readingSurface?.document === liveDocument && sourceRenderer.acceptsReadingInput)
        controller.togglePreview()
        run(0.06)
        controller.togglePreview()
        precondition(sourceRenderer.readingSurface?.document === liveDocument)
        settle()
        controller.togglePreview()
        settle()
        precondition(source.isVisible && source.alphaValue == 1 && source.windowNumber == windowNumber)
        precondition(sourceSurface.visual === sourceRenderer && sourceRenderer.expansion == 0)
        precondition(sourceRenderer.readingSurface == nil && !source.handlesPaperPinch)
        controller.hide(restoreFocus: false); run(0.25)
        print("PASS: one window/renderer/document through opening, magnification and reversal; same card after close")
    }
}
