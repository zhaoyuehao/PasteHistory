import AppKit
import SwiftUI

/// Real preview windows with an isolated database; no clipboard or sync writes.
@main
struct PreviewTextSmoke {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Settings.shared.iCloudSync = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preview-text-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipStore(directory: directory)
        let text = "FIRST LINE — 第一行\n" + (1...6000).map { "Line \($0) — 完整预览，中文与 emoji 👩🏽‍💻，保留换行。\n" }.joined() + "LAST LINE — 最后一行"
        let first = ClipItem(kind: .text, text: text, sourceApp: "Preview regression")
        let second = ClipItem(kind: .text, text: "SECOND RECORD — 第一行\n" + text,
                              sourceApp: "Preview regression", createdAt: Date().addingTimeInterval(-1))
        let image = ClipItem(kind: .image, sourceApp: "OCR regression",
                             createdAt: Date().addingTimeInterval(-2), ocrText: text)
        [first, second, image].forEach { store.syncDatabase.upsert($0) }
        store.refresh()
        let pairing = PairModel(readConnection: { ("", "") }, startService: {}, renewCode: {})
        let controller = PanelController(store: store, observesDesktopFocus: false, pairing: pairing)
        func run(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func scrolls(_ view: NSView) -> [PreviewZoomScrollView] {
            (view as? PreviewZoomScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures.append(message) }
        }
        controller.show()
        run(0.6)
        controller.togglePreview()
        run(0.6)
        var panel: NSPanel { controller.previewWindow! }
        func checkText(_ expected: String, _ context: String) {
            let scroll = scrolls(panel.contentView!).first!
            let view = scroll.documentView as! NSTextView
            check(view.string == expected, "\(context): complete text, including final line")
            print("Viewport: \(scroll.documentVisibleRect), document: \(view.frame)")
            check(abs(scroll.documentVisibleRect.minY) < 1, "\(context): starts at the first line")
            view.scrollToEndOfDocument(nil)
            run()
            let last = NSRange(location: max(0, (view.string as NSString).length - 1), length: 1)
            view.layoutManager!.ensureLayout(forCharacterRange: last)
            let glyphs = view.layoutManager!.glyphRange(forCharacterRange: last, actualCharacterRange: nil)
            let rect = view.layoutManager!.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
                .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            check(scroll.documentVisibleRect.intersects(rect), "\(context): final line is reachable by scrolling")
        }
        checkText(text, "Initial open")
        controller.togglePreview()
        run(0.6)
        controller.togglePreview()
        run(0.6)
        checkText(text, "Reopen after reading the end")
        controller.panelModel.select(1)
        run(0.6)
        checkText(second.text!, "Switch to another long record")
        controller.panelModel.select(0)
        run(0.6)
        checkText(text, "Switch back")
        controller.panelModel.select(2)
        run(0.6)
        let imageScroll = scrolls(panel.contentView!).first as! PreviewImageScrollView
        check(imageScroll.sheet.recognizedText.string == ClipPresentation(item: image).imageDetails,
              "Image OCR retains the complete text beyond 100,000 characters")
        controller.panelModel.select(0)
        run(0.6)
        let face = panel.contentView!
        let bitmap = face.bitmapImageRepForCachingDisplay(in: face.bounds)!
        face.cacheDisplay(in: face.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/preview-text.png"))
        fflush(stdout)
        if CommandLine.arguments.contains("--interactive") {
            panel.makeKeyAndOrderFront(nil)
            app.activate()
            app.run()
        }
        controller.hide(restoreFocus: false)
        run()
        precondition(failures.isEmpty, failures.joined(separator: "; "))
    }
}
