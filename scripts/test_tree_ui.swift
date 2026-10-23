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
        UserDefaults.standard.set(true, forKey: "showDesktopTree")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ivory-ui-" + UUID().uuidString)
        let store = ClipStore(directory: temporary)
        let sampleImage = NSImage(size: NSSize(width: 80, height: 60))
        sampleImage.lockFocus()
        NSColor(red: 0.6, green: 0.7, blue: 0.65, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 80, height: 60).fill()
        NSColor(red: 0.88, green: 0.85, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 35, y: 12, width: 32, height: 32)).fill()
        sampleImage.unlockFocus()
        let thumbnail = NSBitmapImageRep(data: sampleImage.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        for index in 0..<72 {
            let titles = [
                "记下灵感，让它生长。纸签系在真实的枝头，保留分枝之间的空隙。",
                "A quieter place for ideas. Keep the tree visible and the words readable.",
                "今天的设计草稿：八条记录，短绳悬挂，旋转时仍可阅读。", "https://example.com/design\n阅读、检索与灵感收藏",
                "把想法留在枝头\n周五下午三点讨论设计方案。", "明天，也有新枝。先保存灵感，再在需要时迅速找回。",
            ]
            store.syncDatabase.upsert(
                ClipItem(
                    kind: index % 6 == 5 ? .image : .text, text: titles[index % 6] + " · \(index+1)",
                    sourceApp: ["备忘录", "Safari", "微信", "Obsidian", "访达", "邮件"][index % 6],
                    createdAt: Date().addingTimeInterval(Double(-index)),
                    thumbnailData: index % 6 == 5 ? thumbnail : nil))
        }
        store.refresh()
        let model = HistoryViewModel(store: store)
        var copied: UUID?
        var pasted: UUID?
        let window = HistoryPanel(
            contentRect: NSRect(x: 100, y: 100, width: 860, height: 900),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let root = HistoryView(
            store: store, model: model,
            onPaste: { pasted = $0.id }, onCopyOnly: { copied = $0.id },
            onClose: { window.orderOut(nil) }, onPreview: {},
            onTreeModeChanged: { window.applyPresentation(tree: $0) })
        let hosting = NSHostingView(rootView: root)
        window.title = "PasteHistory — Desktop Tree Preview"
        window.contentView = hosting
        window.applyPresentation(tree: true)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        func run(_ seconds: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func post(_ name: Notification.Name) {
            NotificationCenter.default.post(name: name, object: nil)
            run()
        }
        func scene(in view: NSView) -> IvoryTreeSceneView? {
            if let tree = view as? IvoryTreeSceneView { return tree }
            return view.subviews.lazy.compactMap { scene(in: $0) }.first
        }
        run(1)
        precondition(scene(in: hosting)?.loadError == nil)
        precondition(scene(in: hosting) != nil, "Packaged scene must appear")
        precondition(!window.isOpaque && !window.hasShadow && !window.styleMask.contains(.titled))
        precondition(
            window.canBecomeKey && window.isKeyWindow, "Borderless search must receive keyboard input")
        let corner = NSBitmapImageRep(data: scene(in: hosting)!.snapshot().tiffRepresentation!)!
        precondition(corner.colorAt(x: 0, y: 0)!.alphaComponent < 0.01, "Tree background must be transparent")
        let surface = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: surface)
        precondition(
            surface.colorAt(x: 0, y: 0)!.alphaComponent < 0.01, "Hosting view must not add an opaque panel")
        var keyboard = HistoryKeyboardState()
        precondition(keyboard.spacePreviews(query: "two words", composing: false, tree: true))
        keyboard.navigate()
        precondition(keyboard.spacePreviews(query: "two words", composing: false, tree: true))
        precondition(!keyboard.spacePreviews(query: "two words", composing: true, tree: true))
        keyboard.edit()
        precondition(keyboard.spacePreviews(query: "two words", composing: false, tree: true))
        let first = model.current!.id
        post(.phMoveDown)
        precondition(model.safeSelection == 1)
        post(.phCopyOnly)
        precondition(copied == model.current?.id)
        post(.phConfirm)
        precondition(pasted == model.current?.id)
        let pinned = model.current!.id
        post(.phPin)
        precondition(model.results.first?.id == pinned && model.results.first?.pinned == true)
        post(.phPin)
        model.select(1); run()
        post(.phToggleTree)
        precondition(scene(in: hosting) == nil, "List toggle must remove 3D renderer")
        precondition(model.safeSelection == 1)
        precondition(window.isOpaque && window.styleMask.contains(.titled))
        post(.phToggleTree)
        precondition(scene(in: hosting) != nil)
        precondition(!window.isOpaque && !window.styleMask.contains(.titled))
        store.query = "设计草稿"
        run(0.8)
        precondition(!model.results.isEmpty && model.results.allSatisfy { $0.summary.contains("设计草稿") })
        store.query = ""
        run(0.8)
        post(.phPageDown)
        precondition(model.safeSelection == 8, "Keyboard paging must reach the next branch group")
        post(.phPageUp)
        precondition(model.safeSelection == 0)
        model.select(8)
        run()
        let seventh = model.current!.id
        precondition(seventh != first)
        precondition(scene(in: hosting)?.cardFrames[seventh] != nil, "Next page must contain selected record")
        model.select(59)
        run(1)
        precondition(model.results.count == 72, "Tree navigation must load remaining records")
        store.query = "no-such-entry-xyz"
        run(0.8)
        precondition(model.results.isEmpty && model.current == nil)
        store.query = ""
        run(0.8)
        precondition(model.safeSelection == 0 && model.current?.id == first)
        window.setContentSize(NSSize(width: 340, height: 360))
        run()
        precondition(scene(in: hosting)!.bounds.height > 50, "Compact panel must retain a usable viewport")
        window.setContentSize(NSSize(width: 860, height: 900))
        run()
        let removed = model.current!.id
        post(.phDelete)
        precondition(!model.results.contains { $0.id == removed } && store.matchCount == 71 && store.syncDatabase.get(id: removed) == nil)
        // Exercise the real controller/preview/key routing with the same isolated store.
        window.orderOut(nil)
        let controller = PanelController(store: store)
        controller.show()
        run(0.5)
        func key(_ code: UInt16, chars: String = "", mods: NSEvent.ModifierFlags = []) -> NSEvent? {
            controller.handle(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
        }
        store.query = "设计"
        run(0.7)
        precondition(controller.panelModel.results.count == 24)
        precondition(key(49, chars: " ") == nil)
        run(0.3)
        precondition(controller.isPreviewVisible, "Space must preview immediately after search")
        _ = key(125)
        run(0.2)
        precondition(controller.panelModel.safeSelection == 1 && controller.isPreviewVisible,
                     "Arrow selection must keep filtered preview open")
        _ = key(49, chars: " ")
        run(0.2)
        precondition(!controller.isPreviewVisible)
        precondition(key(49, chars: " ", mods: [.shift]) != nil,
                     "Shift-Space must remain available to type multiword queries")
        let liveWindow = NSApp.windows.first { $0.isVisible && $0 is HistoryPanel }!
        let liveScene = scene(in: liveWindow.contentView!)!
        let clickedID = controller.panelModel.results[3].id
        let rect = liveScene.cardFrames[clickedID]!
        let clickPoint = NSPoint(x: rect.midX, y: liveScene.bounds.height - rect.midY)
        let hit = liveWindow.contentView!.hitTest(liveScene.convert(clickPoint, to: liveWindow.contentView!))
        precondition(hit === liveScene, "Search must not overlay the tree's mouse hit area")
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: liveScene.convert(clickPoint, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: liveWindow.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        liveScene.mouseDown(with: mouse(.leftMouseDown))
        liveScene.mouseUp(with: mouse(.leftMouseUp))
        run(0.2)
        precondition(controller.panelModel.current?.id == clickedID, "Filtered paper click must select")
        _ = key(49, chars: " ")
        run(0.2)
        precondition(controller.isPreviewVisible)
        // A realistic long clip exercises the native, non-contiguous text layout.
        let longText = String(repeating: "设计：长文本预览应按可见段落排版，方向键直接切换。\n", count: 4000)
        store.syncDatabase.upsert(ClipItem(kind: .text, text: longText, sourceApp: "Regression"))
        store.refresh()
        run(0.3)
        controller.panelModel.select(0)
        run(0.3)
        var slowest: TimeInterval = 0
        for _ in 0..<8 {
            let start = Date()
            _ = key(125)
            run(0.04)
            _ = key(126)
            run(0.04)
            slowest = max(slowest, Date().timeIntervalSince(start))
        }
        precondition(controller.isPreviewVisible && controller.panelModel.safeSelection == 0)
        print("Preview 100k-text navigation: slowest down/up pair = \(Int(slowest*1000)) ms")
        _ = key(53)
        run(0.2)
        precondition(!controller.isPreviewVisible && controller.isVisible)
        store.query = ""
        run(0.5)
        print(
            "PASS: borderless transparent key window, filtered search, packaged resource, shared selection/copy/paste/pin/delete, list/tree toggle, page selection, lazy loading, empty search, query reset, compact panel"
        )
        fflush(stdout)
        if CommandLine.arguments.contains("--interactive") { app.run() }
        controller.hide()
        run(0.2)
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: temporary)
    }
}
