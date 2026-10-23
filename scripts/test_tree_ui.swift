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
        UserDefaults.standard.removeObject(forKey: "desktopTreeScale")
        UserDefaults.standard.removeObject(forKey: "desktopTreeOrigin")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ivory-ui-" + UUID().uuidString)
        let store = ClipStore(directory: temporary)
        // Round-trip the actual drag writers through an isolated pasteboard.
        let dragBoard = NSPasteboard.withUniqueName()
        defer { dragBoard.releaseGlobally() }
        func roundTrip(_ item: ClipItem) -> [NSPasteboardItem] {
            dragBoard.clearContents()
            guard let writers = ClipDragPayload.writers(for: item, imagesDirectory: store.imagesDirectory) else { preconditionFailure("Missing drag payload") }
            precondition(dragBoard.writeObjects(writers))
            return dragBoard.pasteboardItems!
        }
        let dragText = "Native drag test — 中文\nsecond line"
        precondition(roundTrip(ClipItem(kind: .text, text: dragText))[0].string(forType: .string) == dragText)
        let fileA = temporary.appendingPathComponent("first file.txt")
        let fileB = temporary.appendingPathComponent("第二份.txt")
        try Data("A".utf8).write(to: fileA)
        try Data("B".utf8).write(to: fileB)
        let draggedFiles = roundTrip(ClipItem(kind: .files, filePaths: [fileA.path, fileB.path]))
        precondition(draggedFiles.count == 2)
        precondition(draggedFiles.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)) } == [fileA, fileB])
        precondition(ClipDragPayload.writers(for: ClipItem(kind: .files, filePaths: [fileA.path, "/missing-drag-file"]), imagesDirectory: store.imagesDirectory) == nil)
        let sampleImage = NSImage(size: NSSize(width: 80, height: 60))
        sampleImage.lockFocus()
        NSColor(red: 0.6, green: 0.7, blue: 0.65, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 80, height: 60).fill()
        NSColor(red: 0.88, green: 0.85, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 35, y: 12, width: 32, height: 32)).fill()
        sampleImage.unlockFocus()
        let thumbnail = NSBitmapImageRep(data: sampleImage.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        let savedImage = store.saveImage(sampleImage)!
        let draggedImage = roundTrip(ClipItem(kind: .image, text: "image caption", imageFile: savedImage.name))[0]
        precondition(draggedImage.data(forType: .png) == (try! Data(contentsOf: store.imagesDirectory.appendingPathComponent(savedImage.name))))
        let exportedImage = URL(string: draggedImage.string(forType: .fileURL)!)!
        precondition(FileManager.default.fileExists(atPath: exportedImage.path))
        precondition(draggedImage.string(forType: .string) == "image caption")
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
                    imageFile: index % 6 == 5 ? savedImage.name : nil,
                    sourceApp: ["备忘录", "Safari", "微信", "Obsidian", "访达", "邮件"][index % 6],
                    createdAt: Date().addingTimeInterval(Double(-index)),
                    thumbnailData: index % 6 == 5 ? thumbnail : nil))
        }
        store.refresh()
        if CommandLine.arguments.contains("--drag-interactive") {
            let date = Date()
            store.syncDatabase.upsert(ClipItem(kind: .text, text: "Drag fixture: 中文 text\nsecond line", createdAt: date))
            store.syncDatabase.upsert(ClipItem(kind: .image, text: "Drag fixture: image", imageFile: savedImage.name, createdAt: date.addingTimeInterval(-0.01), thumbnailData: thumbnail))
            store.syncDatabase.upsert(ClipItem(kind: .files, filePaths: [fileA.path, fileB.path], sourceApp: "Drag fixture: files", createdAt: date.addingTimeInterval(-0.02)))
            store.refresh()
            let controller = PanelController(store: store)
            let delegate = TreeHarnessDelegate(controller: controller)
            app.delegate = delegate
            controller.show()
            store.query = "Drag fixture"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let index = CommandLine.arguments.contains("--drag-image") ? 1 : (CommandLine.arguments.contains("--drag-files") ? 2 : 0)
                controller.panelModel.select(index)
                guard let tree = NSApp.windows.first(where: { $0 is HistoryPanel && $0.isVisible }) as? HistoryPanel,
                      let item = controller.panelModel.current,
                      let original = tree.paper(for: item.id)?.contentView as? TreePaperSurface else { return }
                // A key-capable fixture lets native automation bind the actual
                // production drag source, independently of the tiny search window.
                let fixture = TreeInteractionPanel(owner: tree, role: .layout)
                fixture.title = "拖放测试纸签"
                let view = TreePaperSurface()
                view.recordID = item.id
                view.paint = original.paint
                view.setAccessibilityLabel(item.summary)
                fixture.contentView = view
                let screen = NSScreen.screens.first!.visibleFrame
                fixture.setFrame(NSRect(x: screen.minX + 150, y: screen.midY, width: original.bounds.width, height: original.bounds.height), display: true)
                tree.showIslandIfNeeded(fixture)
                fixture.makeKey()
                delegate.inspectionWindow = fixture
            }
            withExtendedLifetime(delegate) { app.run() }
            return
        }
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
            window.canBecomeKey && (window.isKeyWindow || window.islands.contains { $0.isKeyWindow }), "Borderless search must receive keyboard input")
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
        let treeWindow = liveWindow as! HistoryPanel
        precondition(treeWindow.ignoresMouseEvents, "Decorations and all transparent gaps must pass through at OS window level")
        precondition(treeWindow.islands.filter { $0.role == .paper }.count == 8)
        precondition(treeWindow.islands.filter { $0.role == .search }.count == 1)
        treeWindow.focusSearch()
        precondition(treeWindow.islands.first { $0.role == .search }?.firstResponder is NSTextView,
                     "Showing the tree must focus its native search editor for direct typing")
        let paperWindow = treeWindow.islands.first { ($0.contentView as? TreePaperSurface)?.recordID == clickedID }!
        let paperSurface = paperWindow.contentView as! TreePaperSurface
        precondition(paperWindow.frame.width < 200 && paperWindow.frame.height < 160)
        func mouse(_ type: NSEvent.EventType, view: NSView, point: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber,
                context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
        }
        let middle = NSPoint(x: paperSurface.bounds.midX, y: paperSurface.bounds.midY)
        paperSurface.mouseDown(with: mouse(.leftMouseDown, view: paperSurface, point: middle))
        paperSurface.mouseUp(with: mouse(.leftMouseUp, view: paperSurface, point: middle))
        run(0.2)
        precondition(controller.panelModel.current?.id == clickedID, "Filtered paper click must select")
        _ = key(49, chars: " ")
        run(0.2)
        precondition(controller.isPreviewVisible, "Preview missing: tree visible=\(controller.isVisible), front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
        _ = key(49, chars: " ")
        run(0.25)
        let sourcePaper = controller.previewPaper!.frame
        _ = key(49, chars: " ")
        let openingSheet = NSApp.windows.first { $0.isVisible && $0.title == "纸签预览过渡" }!
        precondition(openingSheet.frame == sourcePaper, "Preview must start at the selected paper, not the whole tree")
        run(0.07)
        precondition(openingSheet.frame.width > sourcePaper.width, "Paper must visibly grow toward preview")
        _ = key(49, chars: " ") // interrupt opening with close
        run(0.04)
        _ = key(49, chars: " ") // reopen during return flight
        run(0.3)
        precondition(controller.isPreviewVisible)
        precondition(!NSApp.windows.contains { $0.isVisible && $0.title == "纸签预览过渡" }, "No stale flight may survive rapid toggling")
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
        precondition(!controller.isPreviewVisible && controller.isVisible,
                     "Esc must close only preview: preview=\(controller.isPreviewVisible), tree=\(controller.isVisible)")
        // A rejected/missing payload cancels the click and never moves the tree.
        let prepareDrag = treeWindow.prepareDrag
        treeWindow.prepareDrag = { _ in { nil } }
        let originalFrame = treeWindow.frame
        let originalRotation = liveScene.scene!.rootNode.childNodes[0].eulerAngles
        let currentPaper = treeWindow.islands.first { $0.role == .paper }!.contentView as! TreePaperSurface
        let center = NSPoint(x: currentPaper.bounds.midX, y: currentPaper.bounds.midY)
        let moved = NSPoint(x: center.x+35, y: center.y+12)
        currentPaper.mouseDown(with: mouse(.leftMouseDown, view: currentPaper, point: center))
        currentPaper.mouseDragged(with: mouse(.leftMouseDragged, view: currentPaper, point: moved))
        currentPaper.mouseUp(with: mouse(.leftMouseUp, view: currentPaper, point: moved))
        run(0.1)
        precondition(treeWindow.frame == originalFrame)
        treeWindow.prepareDrag = prepareDrag
        // Freeze the source while the native session owns it. A result refresh
        // during dragging must be reconciled even after rendering has settled.
        let beforeDrag = Set(treeWindow.islands.compactMap { ($0.contentView as? TreePaperSurface)?.recordID })
        treeWindow.dragInProgress = true
        treeWindow.onDragBegan?()
        controller.hide(restoreFocus: false)
        precondition(controller.isVisible, "External activation cannot destroy an active native drag")
        precondition(key(53) != nil && key(36) != nil, "Drag tracking owns Escape and Return")
        store.query = "A quieter"
        run(0.6)
        precondition(Set(treeWindow.islands.compactMap { ($0.contentView as? TreePaperSurface)?.recordID }) == beforeDrag)
        treeWindow.finishPaperDrag(operation: .copy)
        run(0.25)
        precondition(!controller.isVisible, "Accepted drop dismisses tree without reactivating a previous app")
        store.query = "设计"
        controller.show()
        run(0.5)
        let visibleIDs = Set(treeWindow.islands.compactMap { ($0.contentView as? TreePaperSurface)?.recordID })
        precondition(visibleIDs.isSubset(of: Set(controller.panelModel.results.map(\.id))), "No stale cards after drag refresh")
        precondition(liveScene.scene!.rootNode.childNodes[0].eulerAngles.y == originalRotation.y)
        controller.beginTreeLayout()
        run(0.4)
        precondition(controller.layoutEditing && controller.isVisible)
        precondition(treeWindow.islands.filter { $0.role == .paper }.allSatisfy { ($0.contentView as? TreePaperSurface)?.enabled == false })
        precondition(!treeWindow.islands.contains { $0.role == .search })
        let controls = treeWindow.islands.first { $0.role == .layout }!
        precondition(controls.isKeyWindow, "Layout controls must support native keyboard focus")
        func handle(in view: NSView) -> TreeMoveHandleView? {
            if let handle = view as? TreeMoveHandleView { return handle }
            return view.subviews.lazy.compactMap { handle(in: $0) }.first
        }
        let grip = handle(in: controls.contentView!)!
        let gripPoint = NSPoint(x: 20, y: 15)
        grip.mouseDown(with: mouse(.leftMouseDown, view: grip, point: gripPoint))
        grip.mouseDragged(with: mouse(.leftMouseDragged, view: grip, point: NSPoint(x: 55, y: 15)))
        grip.mouseUp(with: mouse(.leftMouseUp, view: grip, point: NSPoint(x: 55, y: 15)))
        precondition(treeWindow.frame.origin != originalFrame.origin, "Only the explicit grip moves the tree")
        NotificationCenter.default.post(name: .phTreeSize, object: 0.82)
        run(0.3)
        precondition(treeWindow.frame.height < originalFrame.height)
        precondition(key(36, chars: "\r") != nil, "Return in layout mode must not paste")
        _ = key(53)
        run(0.3)
        precondition(!controller.layoutEditing && controller.isVisible)
        precondition(treeWindow.islands.contains { $0.role == .search })
        precondition(!treeWindow.islands.contains { $0.role == .layout })
        precondition(treeWindow.islands.filter { $0.role == .paper }.allSatisfy { !$0.ignoresMouseEvents })
        controller.hide(restoreFocus: false)
        run(0.3)
        precondition(treeWindow.islands.allSatisfy { !$0.isVisible }, "Dismissal must leave no input windows behind")
        controller.beginTreeLayout()
        run(0.3)
        precondition(controller.layoutEditing && treeWindow.islands.contains { $0.role == .layout },
                     "Layout invoked while hidden must still create controls")
        controller.endTreeLayout()
        run(0.3)
        precondition(!controller.layoutEditing && controller.isVisible)
        store.query = ""
        run(0.5)
        // Render the native display and bounded child surfaces into one synthetic-data artifact.
        let rendered = NSImage(size: treeWindow.frame.size)
        rendered.lockFocus()
        liveScene.snapshot().draw(in: liveScene.bounds)
        let parent = treeWindow.contentView!
        let parentBitmap = parent.bitmapImageRepForCachingDisplay(in: parent.bounds)!
        parent.cacheDisplay(in: parent.bounds, to: parentBitmap)
        NSImage(cgImage: parentBitmap.cgImage!, size: parent.bounds.size).draw(in: parent.bounds)
        for child in treeWindow.islands where child.isVisible {
            guard let view = child.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let frame = treeWindow.convertFromScreen(child.frame)
            NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: frame)
        }
        rendered.unlockFocus()
        let bitmap = NSBitmapImageRep(data: rendered.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/tree-boundary-preview.png"))
        print(
            "PASS: borderless transparent key window, filtered search, packaged resource, shared selection/copy/paste/pin/delete, list/tree toggle, page selection, lazy loading, empty search, query reset, compact panel, OS click-through, bounded paper/search windows, drag payload round trips, paper-origin preview and interruptible return, explicit move/size mode, clean dismissal"
        )
        fflush(stdout)
        if CommandLine.arguments.contains("--interactive") {
            let delegate = TreeHarnessDelegate(controller: controller)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
        controller.hide()
        run(0.2)
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: temporary)
    }
}

@MainActor final class TreeHarnessDelegate: NSObject, NSApplicationDelegate {
    let controller: PanelController
    var inspectionWindow: TreeInteractionPanel?
    init(controller: PanelController) { self.controller = controller }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        if let inspectionWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { inspectionWindow.orderFrontRegardless(); inspectionWindow.makeKey() }
        }
        return true
    }
}
