// Manual cross-process native drag target. Accepts only synthetic smoke fixtures.
// Build as a separate app, then drag cards from test_tree_ui.sh --drag-interactive.
import AppKit

final class Receiver: NSView {
    var message = "将测试纸签拖到此处 · 文字 / 图片 / 两个文件"
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.string, .png, .fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(message)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: NSRect) {
        NSColor(white: 0.2, alpha: 1).setFill(); bounds.fill()
        (message as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 19)])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let items = sender.draggingPasteboard.pasteboardItems ?? []
        let mask = sender.draggingSourceOperationMask
        var result = ""
        if items.count == 2 {
            let urls = items.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)) }
            guard urls.count == 2,
                  (try? String(contentsOf: urls[0], encoding: .utf8)) == "A",
                  (try? String(contentsOf: urls[1], encoding: .utf8)) == "B" else { return false }
            result = "FILES: received both originals"
        } else if let data = items.first?.data(forType: .png) {
            guard NSImage(data: data) != nil,
                  let url = items.first?.string(forType: .fileURL).flatMap(URL.init(string:)),
                  (try? Data(contentsOf: url)) == data else { return false }
            result = "IMAGE: received PNG and readable export URL"
        } else if items.first?.string(forType: .string) == "Drag fixture: 中文 text\nsecond line" {
            result = "TEXT: received exact multiline Unicode text"
        } else { return false }
        guard mask == .copy else { return false }
        message = "PASS " + result + " · COPY ONLY"
        setAccessibilityLabel(message); needsDisplay = true
        print(message); fflush(stdout)
        return true
    }
}
@main struct DragReceiver {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let visible = NSScreen.screens.first!.visibleFrame
        let window = NSWindow(contentRect: visible.insetBy(dx: 25, dy: 25), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "PasteHistory — 本地拖放验证"
        window.contentView = Receiver(frame: NSRect(origin: .zero, size: window.frame.size))
        window.makeKeyAndOrderFront(nil)
        app.activate()
        app.run()
    }
}
