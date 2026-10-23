// Compile with IvoryTreeScene.swift. Uses synthetic entries only; no clipboard/database access.
import AppKit
import SceneKit

@main
struct TreeSmoke {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        precondition(args.count >= 3, "Usage: tree-smoke asset.scn output-directory [--interactive]")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let asset = URL(fileURLWithPath: args[1])
        let loaded = try SCNScene(url: asset)
        let (lo, hi) = loaded.rootNode.boundingBox
        precondition(hi.y-lo.y > 8 && hi.z-lo.z > 2, "Tree must have real depth")
        precondition(loaded.rootNode.childNodes.filter { $0.name?.hasPrefix("Bird_") == true }.count == 5)
        let view = IvoryTreeSceneView(url: asset)
        precondition(view.loadError == nil)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 440, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Ivory Tree — 3D Preview"
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let entries = ["记下灵感，让它生长", "A quieter place for ideas", "今天的设计草稿", "https://example.com", "把想法留在枝头", "明天，也有新枝"].enumerated().map { IvoryTreeEntry(id: UUID(), title: $0.element, index: $0.offset) }
        view.update(entries: entries, selectedID: entries[0].id)
        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func capture(_ name: String) throws {
            let image = view.snapshot()
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent < 0.01, "Scene backdrop must be transparent")
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        run(1)
        try capture("front.png")
        precondition(view.pointOfView?.camera?.usesOrthographicProjection == false)
        // Verify hit testing on the actual projected card geometry.
        let node = view.scene!.rootNode.childNode(withName: entries[0].id.uuidString, recursively: true)!
        let projected = view.projectPoint(node.worldPosition)
        let point = NSPoint(x: projected.x, y: projected.y)
        precondition(view.entryID(at: point) == entries[0].id, "Visible card must be selectable")
        var selected: UUID?
        view.onSelect = { selected = $0 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, point))
        view.mouseUp(with: event(.leftMouseUp, point))
        precondition(selected == entries[0].id)
        let pivot = view.scene!.rootNode.childNodes[0]
        let originalAngle = pivot.eulerAngles.y
        view.mouseDown(with: event(.leftMouseDown, NSPoint(x: 150, y: 250)))
        view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 255, y: 260)))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 255, y: 260)))
        run(0.8)
        precondition(abs(pivot.eulerAngles.y-originalAngle) > 0.6, "Dragging must rotate actual geometry")
        let rotated = view.projectPoint(node.worldPosition)
        precondition(abs(rotated.x-projected.x) > 10, "Rotation must produce perspective parallax")
        try capture("angle.png")
        view.resetView()
        run(0.8)
        precondition(abs(pivot.eulerAngles.y-originalAngle) < 0.01, "Damped reset must settle")
        view.update(entries: [], selectedID: nil)
        precondition(view.entryID(at: point) == nil, "Removed records must not remain selectable")
        view.update(entries: entries, selectedID: entries[3].id)
        print("PASS: 5 birds, volumetric bounds, perspective, click selection, drag/parallax, damped reset, empty results")
        if args.contains("--interactive") { app.run() }
        view.stopRendering()
    }
}
