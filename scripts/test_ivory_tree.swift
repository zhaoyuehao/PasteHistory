// Production renderer with synthetic records; no clipboard/database access.
import AppKit
import SceneKit

@main
struct TreeSmoke {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        precondition(args.count >= 3)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let asset = URL(fileURLWithPath: args[1])
        let loaded = try SCNScene(url: asset)
        let (lo, hi) = loaded.rootNode.boundingBox
        precondition(hi.y - lo.y > 8 && hi.z - lo.z > 2)
        precondition(
            loaded.rootNode.childNodes.filter { $0.name?.hasPrefix("Bird_") == true }.count == 5)
        let view = IvoryTreeSceneView(url: asset)
        precondition(view.loadError == nil)
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 860, height: 900), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let titles = [
            "记下灵感，让它生长。纸签系在枝头，给分枝留下呼吸的空间。", "A quieter place for ideas. Keep words readable.",
            "今天的设计草稿：八条记录与真实的悬挂关系。", "https://example.com/design\n阅读与灵感收藏", "把想法留在枝头\n周五下午三点讨论设计方案。",
            "明天，也有新枝。先保存，再在需要时迅速找回。", "Ivory_Tree.blend\n白枝与栖鸟", "搜索融入树根，保留所有键盘操作。",
        ]
        let entries = titles.enumerated().map {
            IvoryTreeEntry(
                id: UUID(), title: $0.element, index: $0.offset,
                source: ["备忘录", "Safari", "微信", "Obsidian", "邮件", "备忘录", "访达", "备忘录"][$0.offset],
                date: "10月23日 15:58")
        }
        view.update(entries: entries, selectedID: entries[0].id)
        run(1)
        func capture(_ name: String) throws {
            // Metal isn't included in cacheDisplay. Composite the rendered mesh
            // with the real AppKit paper overlay for documentation previews.
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            view.snapshot().draw(in: view.bounds)
            for overlay in view.subviews {
                let bitmap = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds)!
                overlay.cacheDisplay(in: overlay.bounds, to: bitmap)
                let layerImage = NSImage(size: overlay.bounds.size)
                layerImage.addRepresentation(bitmap)
                layerImage.draw(in: overlay.frame)
            }
            image.unlockFocus()
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            precondition(rep.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
            try rep.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent(name))
        }
        try capture("front.png")
        func occupiedPixels() -> Int {
            let bitmap = NSBitmapImageRep(data: view.snapshot().tiffRepresentation!)!
            var count = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    if bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 { count += 1 }
                }
            }
            return count
        }
        let full = occupiedPixels()
        view.present()
        run(0.055)
        precondition(view.growthProgress < 1)
        let growing = occupiedPixels()
        precondition(
            growing < full * 3 / 4,
            "Growth must reveal geometry from the root, not simply show the whole tree")
        run(0.20)
        precondition(view.growthProgress == 1, "Tree must finish growing within 250 ms")
        let original = view.cardFrames[entries[0].id]!
        let point = NSPoint(x: original.midX, y: view.bounds.height - original.midY)
        precondition(view.entryID(at: point) == entries[0].id)
        func event(_ type: NSEvent.EventType, _ point: NSPoint, mods: NSEvent.ModifierFlags = [])
            -> NSEvent
        {
            NSEvent.mouseEvent(
                with: type, location: view.convert(point, to: nil), modifierFlags: mods, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        var selected: UUID?
        view.onSelect = { selected = $0 }
        view.mouseDown(with: event(.leftMouseDown, point))
        view.mouseUp(with: event(.leftMouseUp, point))
        precondition(selected == entries[0].id)
        let pivot = view.scene!.rootNode.childNodes[0]
        let originalYaw = pivot.eulerAngles.y
        view.mouseDown(with: event(.leftMouseDown, NSPoint(x: 400, y: 500), mods: [.option]))
        view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 510, y: 500), mods: [.option]))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 510, y: 500), mods: [.option]))
        run(0.8)
        precondition(abs(pivot.eulerAngles.y - originalYaw) > 0.8)
        precondition(
            abs(view.cardFrames[entries[0].id]!.midX - original.midX) > 20,
            "Paper must follow the rotating attachment")
        try capture("angle.png")
        view.mouseDown(with: event(.leftMouseDown, NSPoint(x: 400, y: 500), mods: [.option]))
        view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 1200, y: 500), mods: [.option]))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 1200, y: 500), mods: [.option]))
        run(0.9)
        precondition(
            pivot.eulerAngles.y - originalYaw > 2 * .pi, "Yaw must allow more than a full revolution")
        view.resetView()
        run(0.9)
        precondition(abs(pivot.eulerAngles.y - originalYaw) < 0.01)
        // Plain drag moves the window; only Option-drag rotates. Tiny pointer jitter is a click.
        let start = window.frame.origin
        view.mouseDown(with: event(.leftMouseDown, NSPoint(x: 400, y: 500)))
        view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 440, y: 520)))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 440, y: 520)))
        precondition(window.frame.origin != start)
        run(0.1)
        precondition(abs(pivot.eulerAngles.y - originalYaw) < 0.01, "Moving must not rotate")
        let second = entries.map { IvoryTreeEntry(id: UUID(), title: $0.title, index: $0.index + 8) }
        view.update(entries: second, selectedID: second[0].id)
        run(0.07)
        precondition(view.isTurningPage)
        precondition(view.entryID(at: point) == nil, "Departing titles must not activate incoming records")
        let third = entries.map { IvoryTreeEntry(id: UUID(), title: $0.title, index: $0.index + 16) }
        view.update(entries: third, selectedID: third[0].id)
        precondition(
            Set(view.cardFrames.keys) == Set(third.map(\.id)),
            "Interrupted page turns must activate only the latest records")
        run(0.4)
        precondition(!view.isTurningPage)
        view.update(entries: [], selectedID: nil)
        precondition(view.entryID(at: point) == nil && view.cardFrames.isEmpty)
        view.update(entries: entries, selectedID: entries[0].id)
        run(0.4)
        print(
            "PASS: five birds, true depth, transparent scene, root growth pixels, 8 attached papers, hit selection, rotation/parallax beyond 360°, damped reset, window drag, interruptible paging, empty results"
        )
        fflush(stdout)
        if args.contains("--interactive") { app.run() }
        view.stopRendering()
        window.orderOut(nil)
    }
}
