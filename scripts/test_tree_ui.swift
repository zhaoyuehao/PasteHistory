// Compiles against production UI/store/model with an isolated, disposable database.
import AppKit
import SwiftUI

@main
struct TreeUISmoke {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // This harness has its own bundle ID. Disable external sync before any action.
        Settings.shared.iCloudSync = false
        UserDefaults.standard.set(true, forKey: "showIvoryTree")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ivory-ui-"+UUID().uuidString)
        let store = ClipStore(directory: temporary)
        for index in 0..<72 {
            let titles = ["记下灵感，让它生长", "A quieter place for ideas", "今天的设计草稿", "https://example.com", "把想法留在枝头", "明天，也有新枝"]
            store.syncDatabase.upsert(ClipItem(kind: .text, text: titles[index % 6]+" · \(index+1)", sourceApp: "Demo", createdAt: Date().addingTimeInterval(Double(-index))))
        }
        store.refresh()
        let model = HistoryViewModel(store: store)
        var copied: UUID?
        var pasted: UUID?
        let root = HistoryView(store: store, model: model,
                               onPaste: { pasted = $0.id }, onCopyOnly: { copied = $0.id },
                               onClose: {}, onPreview: {})
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 647), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "PasteHistory — 3D Wish Tree Preview"
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        func run(_ seconds: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func post(_ name: Notification.Name) { NotificationCenter.default.post(name: name, object: nil); run() }
        func scene(in view: NSView) -> IvoryTreeSceneView? {
            if let tree = view as? IvoryTreeSceneView { return tree }
            return view.subviews.lazy.compactMap { scene(in: $0) }.first
        }
        run(1)
        precondition(scene(in: hosting)?.loadError == nil)
        precondition(scene(in: hosting) != nil, "Packaged scene must appear")
        let first = model.current!.id
        post(.phMoveDown)
        precondition(model.safeSelection == 1)
        post(.phCopyOnly)
        precondition(copied == model.current?.id)
        post(.phConfirm)
        precondition(pasted == model.current?.id)
        post(.phToggleTree)
        precondition(scene(in: hosting) == nil, "List toggle must remove 3D renderer")
        precondition(model.safeSelection == 1)
        post(.phToggleTree)
        precondition(scene(in: hosting) != nil)
        model.select(6); run()
        let seventh = model.current!.id
        precondition(seventh != first)
        precondition(scene(in: hosting)?.scene?.rootNode.childNode(withName: seventh.uuidString, recursively: true) != nil, "Next page must contain selected record")
        model.select(59); run(1)
        precondition(model.results.count == 72, "Tree navigation must load remaining records")
        store.query = "no-such-entry-xyz"; run(0.8)
        precondition(model.results.isEmpty && model.current == nil)
        store.query = ""; run(0.8)
        precondition(model.safeSelection == 0 && model.current?.id == first)
        window.setContentSize(NSSize(width: 340, height: 360)); run()
        precondition(scene(in: hosting)!.bounds.height > 50, "Compact panel must retain a usable viewport")
        window.setContentSize(NSSize(width: 400, height: 647)); run()
        print("PASS: packaged resource, shared selection/copy/paste, list/tree toggle, page selection, lazy loading, empty search, query reset, compact panel")
        fflush(stdout)
        if CommandLine.arguments.contains("--interactive") { app.run() }
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: temporary)
    }
}
