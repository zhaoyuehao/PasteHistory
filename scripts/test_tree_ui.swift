// Compiles against production UI/store/model with an isolated, disposable database.
import AppKit
import SwiftUI
import Vision

@main
struct TreeUISmoke {
    @MainActor static func main() throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        checkPaperMotion()
        // This harness has its own bundle ID. Disable external sync before any action.
        Settings.shared.iCloudSync = false
        // Legacy list preference must not restore the removed UI.
        UserDefaults.standard.set(false, forKey: "showDesktopTree")
        UserDefaults.standard.removeObject(forKey: "desktopTreeScale")
        // A legacy saved position must never override centered presentation.
        UserDefaults.standard.set("{9999, -9999}", forKey: "desktopTreeOrigin")
        for available in [NSRect(x: 0, y: 25, width: 1440, height: 850),
                          NSRect(x: -1920, y: -200, width: 1920, height: 1080),
                          NSRect(x: 1440, y: 900, width: 800, height: 600)] {
            for scale in [0.82, 1.0, 1.14] {
                let frame = PanelController.centeredTreeFrame(in: available, scale: scale)
                precondition(abs(frame.midX - available.midX) < 0.01 && abs(frame.midY - available.midY) < 0.01)
                precondition(available.contains(frame), "Entire tree must fit on small and offset screens")
            }
        }
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
            onClose: { window.orderOut(nil) }, onPreview: {})
        let hosting = NSHostingView(rootView: AnyView(root))
        window.title = "PasteHistory — Desktop Tree Preview"
        window.contentView = hosting
        window.configureTree()
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
        func zoomViews(in view: NSView) -> [PreviewZoomScrollView] {
            (view as? PreviewZoomScrollView).map { [$0] } ?? view.subviews.flatMap { zoomViews(in: $0) }
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
        precondition(keyboard.spacePreviews(composing: false))
        keyboard.navigate()
        precondition(keyboard.spacePreviews(composing: false))
        precondition(!keyboard.spacePreviews(composing: true))
        keyboard.edit()
        precondition(keyboard.spacePreviews(composing: false))
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
        hosting.rootView = AnyView(EmptyView()) // Retire the first harness's notification subscriptions.
        var pairingStarts = 0
        var pairingRevision = 123456
        let pairing = PairModel(readConnection: { ("http://192.0.2.1:8377/#pair=\(pairingRevision)", "") },
                                startService: { pairingStarts += 1 }, renewCode: { pairingRevision += 1 })
        let controller = PanelController(store: store, observesDesktopFocus: false, pairing: pairing)
        controller.show()
        run(0.5)
        // Reopening a warm scene must move all native paper windows with the
        // tree, keep the full silhouette, and never replay individual folds.
        let entranceTree = NSApp.windows.first { $0 is HistoryPanel && $0.isVisible } as! HistoryPanel
        let restingFrame = entranceTree.frame
        func assertCentered(_ frame: NSRect) {
            let available = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)!.visibleFrame
            precondition(abs(frame.midX - available.midX) < 1 && abs(frame.midY - available.midY) < 1,
                         "Every presentation must center the whole tree on the current screen")
        }
        assertCentered(restingFrame)
        controller.hide(restoreFocus: false)
        run(0.2)
        controller.show()
        let startingY = entranceTree.frame.minY
        if !Motion.reduceMotion { precondition(abs(restingFrame.minY-startingY-12) < 1) }
        let relativePins = Dictionary(uniqueKeysWithValues: entranceTree.islands.filter { $0.role == .paper }.map {
            ($0.windowNumber, ($0.paperPin!.y-entranceTree.frame.minY, $0.frame.size))
        })
        run(0.055)
        // Window ordering may occupy the first run-loop pass in this debug
        // harness. Observe a delivered frame rather than assuming a timer fired.
        let firstFrameDeadline = Date().addingTimeInterval(0.10)
        while !Motion.reduceMotion && entranceTree.frame.minY == startingY && Date() < firstFrameDeadline { run(0.005) }
        let midY = entranceTree.frame.minY
        if !Motion.reduceMotion {
            precondition(midY > startingY && midY < restingFrame.minY,
                         "Entrance must show intermediate movement before settling")
        }
        for island in entranceTree.islands where island.role == .paper {
            if let original = relativePins[island.windowNumber] {
                precondition(abs(island.paperPin!.y-entranceTree.frame.minY-original.0) < 1)
                precondition(abs(island.frame.width-original.1.width) < 1,
                             "Entrance papers must not run their page-fold animation")
                precondition(abs(island.alphaValue-entranceTree.alphaValue) < 0.01)
            }
        }
        controller.show() // Already visible: neither geometry nor opacity restarts.
        precondition(entranceTree.frame.minY == midY)
        run(0.17)
        precondition(entranceTree.frame == restingFrame && entranceTree.alphaValue == 1)
        controller.hide(restoreFocus: false)
        run(0.04)
        let interruptedY = entranceTree.frame.minY
        let interruptedAlpha = entranceTree.alphaValue
        controller.show()
        precondition(entranceTree.frame.minY == interruptedY)
        precondition(abs(entranceTree.alphaValue-interruptedAlpha) < 0.001)
        run(0.25)
        precondition(controller.isVisible && entranceTree.frame == restingFrame && entranceTree.alphaValue == 1)
        func key(_ code: UInt16, chars: String = "", mods: NSEvent.ModifierFlags = []) -> NSEvent? {
            controller.handle(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
        }
        func settlePreview() {
            let deadline = Date().addingTimeInterval(1.2)
            while controller.isPreviewAnimating, Date() < deadline { run(0.01) }
            precondition(!controller.isPreviewAnimating,
                         "Preview must settle within its bounded physical response")
        }
        store.query = "设计"
        run(0.7)
        precondition(controller.panelModel.results.count == 24)
        precondition(key(49, chars: " ") == nil)
        run(0.3); settlePreview()
        precondition(controller.isPreviewVisible, "Space must preview immediately after search")
        var followingPreview: NSPanel { controller.previewWindow! }
        let previousPreviewFrame = followingPreview.frame
        _ = key(125)
        run(0.04)
        if !Motion.reduceMotion {
            precondition(hypot(followingPreview.frame.minX - previousPreviewFrame.minX,
                               followingPreview.frame.minY - previousPreviewFrame.minY) > 2,
                         "Arrow selection must visibly move the paper immediately")
        }
        run(0.36)
        precondition(controller.panelModel.safeSelection == 1 && controller.isPreviewVisible,
                     "Arrow selection must keep filtered preview open")
        let nextPin = controller.previewPaper!.paperPin!
        let nextScreen = NSScreen.screens.first { $0.frame.contains(nextPin) }!
        let followingTarget = PreviewPanelController.paperFrame(pin: nextPin, visible: nextScreen.visibleFrame,
                                                               size: previousPreviewFrame.size)
        print("Arrow preview geometry: before=\(previousPreviewFrame), actual=\(followingPreview.frame), target=\(followingTarget)")
        precondition(abs(followingPreview.frame.minX - followingTarget.minX) < 2
            && abs(followingPreview.frame.minY - followingTarget.minY) < 2,
            "Arrow preview must move to the newly selected paper, not replace content at the previous pin")
        func assertPreviewFollowsSelection() {
            let pin = controller.previewPaper!.paperPin!
            let screen = NSScreen.screens.first { $0.frame.contains(pin) }!
            let target = PreviewPanelController.paperFrame(pin: pin, visible: screen.visibleFrame,
                                                          size: previousPreviewFrame.size)
            precondition(abs(followingPreview.frame.minX - target.minX) < 2
                && abs(followingPreview.frame.minY - target.minY) < 2,
                "Preview must settle at the latest selected pin after interrupted navigation")
            precondition(followingPreview.frame.size == previousPreviewFrame.size,
                         "Moving the reading paper must preserve its viewport size")
        }
        // Reverse before the spring settles, then cross a page boundary while
        // its new paper windows are still being created.
        for code: UInt16 in [125, 125, 126, 125, 126] { _ = key(code); run(0.025) }
        run(0.4); settlePreview()
        assertPreviewFollowsSelection()
        controller.panelModel.select(7)
        run(0.4); settlePreview()
        _ = key(125)
        run(0.5)
        precondition(controller.panelModel.safeSelection == 8)
        assertPreviewFollowsSelection()
        _ = key(49, chars: " ")
        run(0.3); settlePreview()
        precondition(!controller.isPreviewVisible)
        controller.panelModel.select(0)
        run(0.4); settlePreview()
        _ = key(49, chars: " ")
        run(0.04)
        _ = key(125) // redirect an unfinished unfold, not a stationary full-size popup
        run(0.04)
        precondition(followingPreview.alphaValue == 1,
                     "Interrupting the unfold keeps the same paper opaque")
        run(0.4); settlePreview()
        assertPreviewFollowsSelection()
        _ = key(49, chars: " ")
        run(0.3); settlePreview()
        precondition(key(49, chars: " ", mods: [.shift]) != nil,
                     "Shift-Space must remain available to type multiword queries")
        let liveWindow = NSApp.windows.first { $0.isVisible && $0 is HistoryPanel }!
        let liveScene = scene(in: liveWindow.contentView!)!
        let clickedID = controller.panelModel.results[3].id
        let treeWindow = liveWindow as! HistoryPanel
        precondition(treeWindow.ignoresMouseEvents, "Decorations and all transparent gaps must pass through at OS window level")
        precondition(treeWindow.islands.filter { $0.role == .paper }.count == 9)
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
        precondition(controller.isPreviewVisible, "A single paper click must open preview")
        run(0.2); settlePreview()
        let clickablePreview = NSApp.windows.first { $0.isVisible && $0.title == L10n.previewTitle } as! PaperPreviewPanel
        let previewFace = clickablePreview.contentView!
        let previewCenter = NSPoint(x: previewFace.bounds.midX, y: previewFace.bounds.midY)
        let previewDragEnd = NSPoint(x: previewCenter.x + 30, y: previewCenter.y)
        clickablePreview.trackClick(mouse(.leftMouseDown, view: previewFace, point: previewCenter))
        clickablePreview.trackClick(mouse(.leftMouseDragged, view: previewFace, point: previewDragEnd))
        clickablePreview.trackClick(mouse(.leftMouseUp, view: previewFace, point: previewDragEnd))
        run(0.1)
        precondition(controller.isPreviewVisible, "Selecting text by dragging must not collapse preview")
        let previewText = zoomViews(in: previewFace).first!.documentView as! NSTextView
        let textPoint = NSPoint(x: 30, y: 15)
        clickablePreview.trackClick(mouse(.leftMouseDown, view: previewText, point: textPoint))
        previewText.setSelectedRange(NSRange(location: 0, length: 1))
        clickablePreview.trackClick(mouse(.leftMouseUp, view: previewText, point: textPoint))
        run(0.1)
        precondition(controller.isPreviewVisible, "Even a short text selection must keep preview open")
        previewText.setSelectedRange(NSRange(location: 0, length: 0))
        clickablePreview.trackClick(mouse(.leftMouseDown, view: previewFace, point: previewCenter))
        clickablePreview.trackClick(mouse(.leftMouseUp, view: previewFace, point: previewCenter))
        run(0.3); settlePreview()
        precondition(!controller.isPreviewVisible && controller.isVisible,
                     "Clicking the expanded paper must collapse it without dismissing the tree")
        precondition(controller.panelModel.current?.id == clickedID && controller.previewPaper?.alphaValue == 1,
                     "Click collapse must restore the same source card")
        _ = key(49, chars: " ")
        run(0.3); settlePreview()
        _ = key(49, chars: " ")
        let returnDeadline = Date().addingTimeInterval(1.5)
        while controller.isPreviewAnimating && Date() < returnDeadline {
            run(0.02)
        }
        precondition(!controller.isPreviewAnimating,
                     "Return flight must complete before testing a fresh opening")
        let sourcePaper = controller.previewPaper!.frame
        _ = key(49, chars: " ")
        let openingSheet = controller.previewWindow!
        precondition(abs(openingSheet.frame.minX-sourcePaper.minX) <= 1 && abs(openingSheet.frame.minY-sourcePaper.minY) <= 1
                     && abs(openingSheet.frame.width-sourcePaper.width) <= 2 && abs(openingSheet.frame.height-sourcePaper.height) <= 2,
                     "The flight canvas must tightly enclose the selected paper, allowing only outward pixel rounding")
        run(0.07)
        precondition(openingSheet.frame.width > sourcePaper.width, "Paper must visibly grow toward preview")
        _ = key(49, chars: " ") // interrupt opening with close
        run(0.04)
        _ = key(49, chars: " ") // reopen during return flight
        run(0.3); settlePreview()
        precondition(controller.isPreviewVisible)
        precondition(!controller.isPreviewAnimating, "No stale flight may survive rapid toggling")
        let expanded = NSApp.windows.first { $0.isVisible && $0.title == L10n.previewTitle }!
        let paperPin = controller.previewPaper!.paperPin!
        let screen = NSScreen.screens.first { $0.frame.contains(paperPin) }!
        let expected = PreviewPanelController.paperFrame(pin: paperPin, visible: screen.visibleFrame,
            size: PreviewPanelController.paperSize(for: controller.panelModel.current))
        precondition(abs(expanded.frame.midX-expected.midX) < 2 && abs(expanded.frame.maxY-expected.maxY) < 2,
                     "Expanded paper stays at its hanging hole, subject only to screen-edge clamping")
        precondition(controller.previewPaper === expanded && controller.previewPaper?.alphaValue == 1,
                     "The source paper itself becomes the reading window")
        precondition(abs(expanded.frame.width / expanded.frame.height - 1.61803398875) < 0.004,
                     "Expanded paper retains a golden rectangle")
        precondition(!expanded.styleMask.contains(.titled) && !expanded.isMovable,
                     "Tree preview must have paper chrome and cannot be dragged away from its branch")
        let face = expanded.contentView!
        face.layoutSubtreeIfNeeded()
        let faceBitmap = face.bitmapImageRepForCachingDisplay(in: face.bounds)!
        face.cacheDisplay(in: face.bounds, to: faceBitmap)
        let paperColor = faceBitmap.colorAt(x: 12, y: faceBitmap.pixelsHigh/2)!.usingColorSpace(.deviceRGB)!
        let expectedColor = IvoryPaperStyle.fill.usingColorSpace(.deviceRGB)!
        precondition(abs(paperColor.redComponent-expectedColor.redComponent) < 0.035 && abs(paperColor.blueComponent-expectedColor.blueComponent) < 0.035,
                     "Expanded face uses the same ivory paper, not the system preview background")
        let composed = NSImage(size: treeWindow.frame.size)
        composed.lockFocus()
        liveScene.snapshot().draw(in: liveScene.bounds)
        let base = treeWindow.contentView!
        let baseBitmap = base.bitmapImageRepForCachingDisplay(in: base.bounds)!
        base.cacheDisplay(in: base.bounds, to: baseBitmap)
        NSImage(cgImage: baseBitmap.cgImage!, size: base.bounds.size).draw(in: base.bounds)
        for child in treeWindow.islands where child.isVisible && child.alphaValue > 0 {
            guard let view = child.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            NSImage(cgImage: rep.cgImage!, size: view.bounds.size).draw(in: treeWindow.convertFromScreen(child.frame))
        }
        NSImage(cgImage: faceBitmap.cgImage!, size: face.bounds.size).draw(in: treeWindow.convertFromScreen(expanded.frame))
        composed.unlockFocus()
        let composedBitmap = NSBitmapImageRep(data: composed.tiffRepresentation!)!
        try composedBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/expanded-paper-preview.png"))
        // Geometry also covers multiple displays, edge cards and small screens.
        for visible in [NSRect(x: -1440, y: 100, width: 1440, height: 900), NSRect(x: 0, y: 0, width: 360, height: 500)] {
            for pin in [NSPoint(x: visible.minX+5, y: visible.minY+5), NSPoint(x: visible.maxX-5, y: visible.maxY-5), NSPoint(x: visible.midX, y: visible.midY)] {
                let fitted = PreviewPanelController.paperFrame(pin: pin, visible: visible)
                precondition(visible.contains(fitted))
                precondition(abs(fitted.width / fitted.height - 1.61803398875) < 0.004, "Screen fitting scales both dimensions together")
            }
        }
        // Open and close share one opaque paper, the same geometry endpoints,
        // and a reversible content phase. Neither direction disappears in place.
        let liveSurface = (expanded.contentView as! TreePaperSurface).visual!.readingSurface!
        let logicalReadingBounds = liveSurface.bounds
        let readingFrameBeforeClose = expanded.frame
        let compactFrameBeforeClose = controller.previewPaper!.paperPose!.frame
        _ = key(49, chars: " ")
        let closingSheet = controller.previewWindow!
        precondition(abs(closingSheet.frame.width-readingFrameBeforeClose.width) <= 2)
        run(0.07)
        precondition(closingSheet === expanded && expanded.alphaValue == 1,
                     "Closing must remain a visible paper returning to its branch, not fade out in place")
        precondition(closingSheet.frame.width < readingFrameBeforeClose.width
                     && closingSheet.frame.width > compactFrameBeforeClose.width)
        precondition(liveSurface.bounds == logicalReadingBounds,
                     "The captured reading layout must remain stable throughout the return")
        let reverseFrame = closingSheet.frame
        let reversePhase = (closingSheet.contentView as! TreePaperSurface).visual!.expansion
        _ = key(49, chars: " ")
        precondition(closingSheet.frame == reverseFrame
                     && (closingSheet.contentView as! TreePaperSurface).visual!.expansion == reversePhase,
                     "Mid-return reopening must preserve the presented geometry and content phase")
        run(0.3); settlePreview()
        precondition(controller.isPreviewVisible && expanded.frame == readingFrameBeforeClose)
        let returnStarted = ProcessInfo.processInfo.systemUptime
        _ = key(49, chars: " ")
        var closingFrames: [(Double, NSImage, NSSize)] = []
        var closingTimeline = "elapsed_ms,width,height,phase\n"
        var previousClosingWidth = readingFrameBeforeClose.width + 2
        var priorPhase: CGFloat = -1
        while controller.isPreviewAnimating && ProcessInfo.processInfo.systemUptime-returnStarted < 1.2 {
            if controller.isPreviewAnimating, let face = (closingSheet.contentView as? TreePaperSurface)?.visual,
               face.expansion != priorPhase {
                precondition(closingSheet.frame.width <= previousClosingWidth+1, "A resting paper must shrink continuously back to its branch")
                precondition(closingSheet.alphaValue == 1)
                previousClosingWidth = closingSheet.frame.width
                priorPhase = face.expansion
                let elapsed = ProcessInfo.processInfo.systemUptime-returnStarted
                closingTimeline += "\(elapsed*1000),\(face.pose.size.width),\(face.pose.size.height),\(face.expansion)\n"
                closingFrames.append((elapsed, face.faceImage(), face.pose.frame.size))
            }
            run(0.004)
        }
        precondition(closingFrames.count >= 6, "Inspect multiple native frames from input through the return")
        let closingStrip = NSImage(size: NSSize(width: readingFrameBeforeClose.width*CGFloat(closingFrames.count), height: readingFrameBeforeClose.height+20))
        closingStrip.lockFocus()
        for (index, frame) in closingFrames.enumerated() {
            let x = CGFloat(index)*readingFrameBeforeClose.width
            frame.1.draw(in: NSRect(x: x, y: closingStrip.size.height-frame.2.height,
                                   width: frame.2.width, height: frame.2.height))
            (String(format: "%.0f ms", frame.0*1000) as NSString).draw(at: NSPoint(x: x+8, y: 2),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
        }
        closingStrip.unlockFocus()
        precondition(!controller.isPreviewVisible && closingSheet.isVisible && !(closingSheet as! TreeInteractionPanel).previewOwnsGeometry)
        precondition(controller.previewPaper?.alphaValue == treeWindow.treeOpacity)
        try closingTimeline.write(toFile: ".build/preview-return-timeline.csv", atomically: true, encoding: .utf8)
        try NSBitmapImageRep(data: closingStrip.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: ".build/preview-symmetric-close.png"))
        _ = key(49, chars: " ")
        run(0.3); settlePreview()
        // Observe actual paper motion: visible travel, monotone settling, exact live-view handoff.
        _ = key(49, chars: " ")
        run(0.3); settlePreview()
        _ = key(49, chars: " ")
        let settlingPaper = controller.previewWindow!
        var widest: CGFloat = 0
        var priorWidth: CGFloat = 0
        var motionFrames: [(NSImage, NSSize)] = []
        for sample in 0..<11 {
            run(0.025)
            if settlingPaper.isVisible {
                precondition(settlingPaper.frame.width >= priorWidth - 1,
                             "An uninterrupted unfold must not bounce or shrink before settling")
                priorWidth = settlingPaper.frame.width
                widest = max(widest, settlingPaper.frame.width)
                if sample % 2 == 0, let view = settlingPaper.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    motionFrames.append((NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size), view.bounds.size))
                }
                if sample >= 5 && !Motion.reduceMotion {
                    precondition(settlingPaper === expanded && expanded.alphaValue == 1,
                                 "The moving paper stays opaque; no delayed full-size preview fades in behind it")
                }
            }
        }
        let strip = NSImage(size: NSSize(width: expected.width * CGFloat(motionFrames.count), height: expected.height * 1.03))
        strip.lockFocus()
        for (index, frame) in motionFrames.enumerated() {
            frame.0.draw(in: NSRect(x: CGFloat(index) * expected.width + (expected.width-frame.1.width)/2,
                                   y: strip.size.height-frame.1.height, width: frame.1.width, height: frame.1.height))
        }
        strip.unlockFocus()
        try NSBitmapImageRep(data: strip.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/preview-motion-frames.png"))
        precondition(widest > expected.width * 0.95 && widest <= expected.width + 1,
                     "Paper must travel to its reading size without ornamental overshoot")
        settlePreview()
        precondition(settlingPaper === expanded && abs(expanded.frame.width-expected.width) < 1)
        let textZoom = zoomViews(in: expanded.contentView!).first!
        let textWidth = textZoom.documentVisibleRect.width
        let zoomPanel = expanded as! PaperPreviewPanel
        // Exercise the same window/point routing gate as real local events.
        // In particular, preview must remain non-key before and after the pinch.
        func nativePinch(_ panel: PaperPreviewPanel, by delta: CGFloat) {
            let point = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
            precondition(panel.routeMagnification(from: panel, at: point, delta: delta, phase: .began), "Pinch must reach live paper: visible=\(panel.isVisible) alpha=\(panel.alphaValue) ignores=\(panel.ignoresMouseEvents) monitor=\(panel.handlesPaperPinch) frame=\(panel.frame)")
            run(0.02)
            precondition(panel.routeMagnification(from: panel, at: NSPoint(x: 20, y: 20), delta: 0, phase: .ended))
            run(0.02)
        }
        treeWindow.focusSearch()
        precondition(!zoomPanel.isKeyWindow && NSApp.keyWindow !== zoomPanel,
                     "Regression must start with search focused and preview unclicked")
        let rejectedFrame = zoomPanel.frame
        precondition(!zoomPanel.routeMagnification(from: treeWindow, at: NSPoint(x: 20, y: 20), delta: 0.5, phase: .began))
        precondition(!zoomPanel.routeMagnification(from: nil, at: NSPoint(x: 20, y: 20), delta: 0.5, phase: .began))
        precondition(!zoomPanel.routeMagnification(from: zoomPanel, at: NSPoint(x: -5, y: 20), delta: 0.5, phase: .began))
        precondition(zoomPanel.frame == rejectedFrame, "Foreign windows and outside points must never zoom the paper")
        let unscaledPaperFrame = expanded.frame
        let textSize = textZoom.convert(NSRect(x: 0, y: 0, width: 100, height: 20), to: nil).size
        let keyBeforePinch = NSApp.keyWindow
        nativePinch(zoomPanel, by: 0.5)
        run(0.1)
        let scaledTextSize = textZoom.convert(NSRect(x: 0, y: 0, width: 100, height: 20), to: nil).size
        precondition(abs(expanded.frame.width / unscaledPaperFrame.width - 1.5) < 0.01
            && abs(scaledTextSize.width / textSize.width - 1.5) < 0.01,
            "Pinching must enlarge the real paper and live text together")
        precondition(!textZoom.allowsMagnification && textZoom.magnification == 1
            && abs(textZoom.documentVisibleRect.width - textWidth) < 1,
            "Text keeps its logical layout; there is no second document zoom")
        precondition(NSApp.keyWindow === keyBeforePinch, "Pinch must not require or steal keyboard focus")
        let enlargedText = textZoom.documentView as! NSTextView
        let enlargedTextPoint = NSPoint(x: 30, y: 15)
        zoomPanel.trackClick(mouse(.leftMouseDown, view: enlargedText, point: enlargedTextPoint))
        enlargedText.setSelectedRange(NSRange(location: 0, length: 1))
        zoomPanel.trackClick(mouse(.leftMouseUp, view: enlargedText, point: enlargedTextPoint))
        run(0.1)
        precondition(controller.isPreviewVisible, "Text selection must remain protected after paper scaling")
        enlargedText.setSelectedRange(NSRange(location: 0, length: 0))
        let scaledPin = controller.previewPaper!.paperPin!
        let scaledTarget = PreviewPanelController.paperFrame(pin: scaledPin, visible: screen.visibleFrame,
            size: expanded.frame.size, magnification: 1.5)
        precondition(abs(expanded.frame.minX - scaledTarget.minX) < 2 && abs(expanded.frame.minY - scaledTarget.minY) < 2,
                     "Scaled paper retains its hanging point except for screen-edge fitting")
        // A realistic long clip exercises the native, non-contiguous text layout.
        let longText = String(repeating: "设计：长文本预览应按可见段落排版，方向键直接切换。\n", count: 4000)
        store.syncDatabase.upsert(ClipItem(kind: .text, text: longText, sourceApp: "Regression"))
        store.refresh()
        run(0.3); settlePreview()
        controller.panelModel.select(0)
        run(0.3); settlePreview()
        let stablePreviewSize = expanded.frame.size
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
        precondition(expanded.frame.size == stablePreviewSize, "Arrow navigation must not repeatedly reflow long text by resizing the paper")
        run(0.4); settlePreview()
        let zoomedPin = controller.previewPaper!.paperPin!
        let zoomedTarget = PreviewPanelController.paperFrame(pin: zoomedPin, visible: screen.visibleFrame,
            size: stablePreviewSize, magnification: 1.5)
        precondition(abs(expanded.frame.minX - zoomedTarget.minX) < 2 && abs(expanded.frame.minY - zoomedTarget.minY) < 2,
                     "Arrow navigation preserves zoom and the scaled hanging point")
        print("Preview 100k-text navigation: slowest down/up pair = \(Int(slowest*1000)) ms")
        _ = key(53)
        run(0.3); settlePreview()
        precondition(!zoomPanel.handlesPaperPinch && !zoomPanel.routeMagnification(from: zoomPanel, at: NSPoint(x: 20, y: 20), delta: 0.5, phase: .began), "Closing must remove the monitor, not just hide its window")
        precondition(controller.previewPaper?.alphaValue == 1, "Closing restores the hanging paper")
        precondition(!controller.isPreviewVisible && controller.isVisible,
                     "Esc must close only preview: preview=\(controller.isPreviewVisible), tree=\(controller.isVisible)")
        // Image content remains searchable by OCR, but the hanging paper is a
        // photograph. Inspect actual rendered pixels and native preview text.
        let recognizedText = "OCR-only-fixture 识别内容：枝头图片优先，文字在展开后阅读。"
        let imageRecord = ClipItem(kind: .image, imageFile: savedImage.name,
            sourceApp: "Image regression", thumbnailData: thumbnail, ocrText: recognizedText)
        store.syncDatabase.upsert(imageRecord)
        store.query = "OCR-only-fixture"
        run(0.7)
        precondition(controller.panelModel.results.map(\.id) == [imageRecord.id], "OCR search remains a data operation")
        let imageEntry = IvoryTreeEntry(item: imageRecord, index: 0)
        precondition(imageEntry.imageFirst && imageEntry.title == L10n.image,
                     "Compact image presentation must not substitute OCR for pixels")
        let imagePaper = controller.previewPaper!.contentView as! TreePaperSurface
        let imageBitmap = NSBitmapImageRep(data: imagePaper.paperImage().tiffRepresentation!)!
        try imageBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/image-first-card.png"))
        let sourceColor = NSBitmapImageRep(data: thumbnail)!.colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!
        var photoPixels = 0
        for y in 0..<imageBitmap.pixelsHigh {
            for x in 0..<imageBitmap.pixelsWide {
                guard let color = imageBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.9 && abs(color.redComponent - sourceColor.redComponent) < 0.035
                    && abs(color.greenComponent - sourceColor.greenComponent) < 0.035 && abs(color.blueComponent - sourceColor.blueComponent) < 0.035 {
                    photoPixels += 1
                }
            }
        }
        print("Photo pixel fraction: \(Double(photoPixels) / Double(imageBitmap.pixelsWide * imageBitmap.pixelsHigh))")
        precondition(Double(photoPixels) / Double(imageBitmap.pixelsWide * imageBitmap.pixelsHigh) > 0.16,
                     "Image pixels must occupy the paper body, not a small side thumbnail")
        try imageBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/image-first-card.png"))
        _ = key(49, chars: " ")
        run(0.5); settlePreview()
        func textViews(in view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }
        let imagePreview = NSApp.windows.first { $0.isVisible && $0.title == L10n.previewTitle }!
        precondition(textViews(in: imagePreview.contentView!).contains { $0.isSelectable && $0.string.contains(recognizedText) },
                     "Expanded image preview must expose selectable OCR text")
        let imageZoom = zoomViews(in: imagePreview.contentView!).first as! PreviewImageScrollView
        let ocrFrame = imageZoom.sheet.recognizedText.frame
        precondition(ocrFrame.minY >= imageZoom.documentVisibleRect.maxY - 1, "First viewport must show only image; OCR begins below the fold")
        precondition(imageZoom.sheet.recognizedText.font!.pointSize == 13, "OCR uses the compact reading type size")
        let readingFrame = imagePreview.frame
        let pictureFrame = imageZoom.sheet.picture.frame
        let unzoomedWidth = imageZoom.documentVisibleRect.width
        let imagePhysicalSize = imageZoom.sheet.picture.convert(imageZoom.sheet.picture.bounds, to: nil).size
        let imagePanel = imagePreview as! PaperPreviewPanel
        nativePinch(imagePanel, by: 0.4)
        run(0.1)
        let enlargedImageSize = imageZoom.sheet.picture.convert(imageZoom.sheet.picture.bounds, to: nil).size
        precondition(abs(imagePreview.frame.width / readingFrame.width - 1.4) < 0.01
            && abs(enlargedImageSize.width / imagePhysicalSize.width - 1.4) < 0.01,
            "Image and paper must enlarge with the same gesture and scale")
        precondition(!imageZoom.allowsMagnification && imageZoom.magnification == 1
            && abs(imageZoom.documentVisibleRect.width - unzoomedWidth) < 1
            && imageZoom.sheet.picture.frame == pictureFrame,
            "Whole-card scaling must preserve the image/OCR document layout")
        // Oversized gestures remain on screen and settle back from the limit.
        nativePinch(imagePanel, by: 4)
        let upperZoomDeadline = Date().addingTimeInterval(0.8)
        while imagePreview.frame.width > readingFrame.width*2+1 && Date() < upperZoomDeadline { run(0.01) }
        precondition(imagePreview.frame.width <= readingFrame.width * 2 + 1
            && imagePreview.screen!.visibleFrame.contains(imagePreview.frame), "Pinch limit must fit the screen")
        imagePanel.magnifyPaper(by: -0.9, phase: .began)
        precondition(imagePreview.frame.width < readingFrame.width, "Lower zoom limit has a small elastic response")
        imagePanel.magnifyPaper(by: 0, phase: .ended)
        let zoomDeadline = Date().addingTimeInterval(0.8)
        while abs(imagePreview.frame.width-readingFrame.width) >= 1 && Date() < zoomDeadline { run(0.01) }
        precondition(abs(imagePreview.frame.width - readingFrame.width) < 1, "Elastic return must settle at default size")
        nativePinch(imagePanel, by: 0.4)
        imageZoom.contentView.scroll(to: NSPoint(x: 0, y: ocrFrame.minY))
        imageZoom.reflectScrolledClipView(imageZoom.contentView)
        run(0.1)
        precondition(imageZoom.documentVisibleRect.intersects(ocrFrame), "Scrolling down exposes OCR in the same document")
        let scrolledFace = imagePreview.contentView!
        let scrolledBitmap = scrolledFace.bitmapImageRepForCachingDisplay(in: scrolledFace.bounds)!
        scrolledFace.cacheDisplay(in: scrolledFace.bounds, to: scrolledBitmap)
        try scrolledBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/image-preview-ocr.png"))
        let closingImageFrame = imagePreview.frame
        let closingOCRViewport = imageZoom.documentVisibleRect
        let closingPictureFrame = imageZoom.sheet.picture.frame
        _ = key(53)
        run(0.045)
        precondition(imagePreview.contentView === scrolledFace && imagePreview.frame == closingImageFrame)
        let closingViewport = imageZoom.documentVisibleRect
        precondition(abs(closingViewport.minY-closingOCRViewport.minY) < 0.5
                     && abs(closingViewport.width-closingOCRViewport.width) < 0.5
                     && abs(closingViewport.height-closingOCRViewport.height) < 0.5
                     && imageZoom.sheet.picture.frame == closingPictureFrame,
                     "OCR return changed its viewport: \(closingOCRViewport) -> \(closingViewport), image \(closingPictureFrame) -> \(imageZoom.sheet.picture.frame)")
        run(0.25); settlePreview()
        _ = key(49, chars: " ")
        run(0.3); settlePreview()
        let reopenedZoom = zoomViews(in: imagePreview.contentView!).first as! PreviewImageScrollView
        precondition(reopenedZoom.magnification == 1 && reopenedZoom.documentVisibleRect.minY < 1,
                     "Reopening returns to the image, rather than leaving OCR or zoom from the previous viewing")
        precondition(imagePreview.frame.size == readingFrame.size, "Closing and reopening must discard whole-card magnification")
        let imageFace = imagePreview.contentView!
        let imageFaceBitmap = imageFace.bitmapImageRepForCachingDisplay(in: imageFace.bounds)!
        imageFace.cacheDisplay(in: imageFace.bounds, to: imageFaceBitmap)
        try imageFaceBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/image-first-preview.png"))
        let loader = PreviewMediaLoader(imagesDirectory: store.imagesDirectory)
        var loaded: PreviewMediaLoader.Asset?
        var fileMetadata: FileMetadata?
        Task {
            loaded = await loader.load(loader.url(for: imageRecord)!, maxPixel: 640)
            fileMetadata = await FileMetadata.read(path: fileA.path)
        }
        run(0.5)
        precondition(loaded?.image != nil && loaded?.pixels == CGSize(width: NSBitmapImageRep(data: thumbnail)!.pixelsWide, height: NSBitmapImageRep(data: thumbnail)!.pixelsHigh),
                     "Preview loader must read the injected store, not the user's global history")
        precondition(fileMetadata?.exists == true && fileMetadata?.bytes == 1, "File preview metadata must come from the filesystem service")
        _ = key(53)
        run(0.3); settlePreview()
        store.query = "设计"
        run(0.7)
        // A rejected/missing payload cancels the click and never moves the tree.
        let prepareDrag = treeWindow.prepareDrag
        treeWindow.prepareDrag = { _ in { nil } }
        let originalFrame = treeWindow.frame
        let originalRotation = liveScene.scene!.rootNode.childNodes[0].eulerAngles
        let currentPaper = treeWindow.islands.first { $0.role == .paper && ($0.contentView as? TreePaperSurface)?.draggable == true }!.contentView as! TreePaperSurface
        let center = NSPoint(x: currentPaper.bounds.midX, y: currentPaper.bounds.midY)
        let moved = NSPoint(x: center.x+35, y: center.y+12)
        currentPaper.mouseDown(with: mouse(.leftMouseDown, view: currentPaper, point: center))
        currentPaper.mouseDragged(with: mouse(.leftMouseDragged, view: currentPaper, point: moved))
        currentPaper.mouseUp(with: mouse(.leftMouseUp, view: currentPaper, point: moved))
        run(0.1)
        precondition(treeWindow.frame == originalFrame)
        precondition(!controller.isPreviewVisible, "Dragging must not also trigger click preview")
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
        precondition(visibleIDs.isSubset(of: Set(controller.panelModel.results.map(\.id)).union([IvoryTreeEntry.phoneSyncID])), "No stale cards after drag refresh")
        precondition(liveScene.scene!.rootNode.childNodes[0].eulerAngles.y == originalRotation.y)
        controller.beginTreeLayout()
        run(0.4); settlePreview()
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
        run(0.3); settlePreview()
        precondition(treeWindow.frame.height < originalFrame.height)
        precondition(key(36, chars: "\r") != nil, "Return in layout mode must not paste")
        _ = key(53)
        run(0.3); settlePreview()
        precondition(!controller.layoutEditing && controller.isVisible)
        precondition(treeWindow.islands.contains { $0.role == .search })
        precondition(!treeWindow.islands.contains { $0.role == .layout })
        precondition(treeWindow.islands.filter { $0.role == .paper }.allSatisfy { !$0.ignoresMouseEvents })
        controller.hide(restoreFocus: false)
        run(0.3); settlePreview()
        precondition(treeWindow.islands.allSatisfy { !$0.isVisible }, "Dismissal must leave no input windows behind")
        controller.beginTreeLayout()
        run(0.3); settlePreview()
        precondition(controller.layoutEditing && treeWindow.islands.contains { $0.role == .layout },
                     "Layout invoked while hidden must still create controls")
        controller.endTreeLayout()
        run(0.3); settlePreview()
        assertCentered(treeWindow.frame)
        precondition(!controller.layoutEditing && controller.isVisible)
        store.query = ""
        run(0.5)
        // Delete follows card navigation, but search editing and IME keep their key.
        let deleteCandidate = controller.panelModel.current!.id
        precondition(key(51) == nil)
        run(0.3); settlePreview()
        precondition(store.syncDatabase.get(id: deleteCandidate) == nil, "Plain Delete removes the selected card")
        store.query = "设计"
        run(0.6)
        _ = key(0, chars: "a") // text input returns keyboard routing to search
        let searchCount = store.totalCount
        precondition(key(51) != nil && key(117) != nil, "Delete must edit a nonempty search query")
        precondition(store.totalCount == searchCount)
        _ = key(125)
        let filteredCandidate = controller.panelModel.current!.id
        let searchWindow = treeWindow.islands.first { $0.role == .search }!
        treeWindow.focusSearch()
        let editor = searchWindow.firstResponder as! NSTextView
        editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(key(51) != nil && store.totalCount == searchCount, "IME Delete cannot remove a card")
        editor.unmarkText()
        precondition(key(117) == nil)
        run(0.3); settlePreview()
        precondition(store.syncDatabase.get(id: filteredCandidate) == nil, "Forward Delete removes the navigated search result")
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
        for child in treeWindow.islands where child.isVisible && child.alphaValue > 0 {
            guard let view = child.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let frame = treeWindow.convertFromScreen(child.frame)
            NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: frame)
        }
        rendered.unlockFocus()
        let bitmap = NSBitmapImageRep(data: rendered.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/tree-boundary-preview.png"))
        let selectedBeforeShortcut = controller.panelModel.current?.id
        precondition(key(37, chars: "l", mods: [.command]) != nil)
        run(0.3); settlePreview()
        precondition(scene(in: treeWindow.contentView!) != nil && !treeWindow.isOpaque,
                     "The removed list shortcut must leave the tree visible")
        precondition(controller.panelModel.current?.id == selectedBeforeShortcut)
        // The permanent phone card has no history row and uses the production
        // preview flight, input boundaries and teardown, with an isolated QR source.
        store.query = ""
        run(0.8)
        let phoneID = IvoryTreeEntry.phoneSyncID
        let phoneIsland = treeWindow.paper(for: phoneID)!
        let phonePin = phoneIsland.paperPin!
        precondition((phoneIsland.contentView as! TreePaperSurface).draggable == false)
        controller.panelModel.select(8)
        run(0.6)
        precondition(treeWindow.paper(for: phoneID) === phoneIsland, "Paging retains the same phone paper window")
        precondition(hypot(phoneIsland.paperPin!.x-phonePin.x, phoneIsland.paperPin!.y-phonePin.y) < 1,
                     "History paging must not relocate the permanent phone card")
        let countBeforePhone = store.matchCount
        let historyBeforePhone = controller.panelModel.current!
        let phoneSurface = phoneIsland.contentView as! TreePaperSurface
        let phoneCenter = NSPoint(x: phoneSurface.bounds.midX, y: phoneSurface.bounds.midY)
        phoneSurface.mouseDown(with: mouse(.leftMouseDown, view: phoneSurface, point: phoneCenter))
        phoneSurface.mouseUp(with: mouse(.leftMouseUp, view: phoneSurface, point: phoneCenter))
        run(0.8)
        precondition(controller.isPreviewVisible && controller.previewSelectionID == phoneID && pairingStarts == 1)
        let phonePreview = controller.previewWindow as! PaperPreviewPanel
        precondition(phonePreview === phoneIsland && phoneIsland.alphaValue == 1 && !phoneIsland.ignoresMouseEvents && phonePreview.handlesPaperPinch)
        precondition(!phonePreview.isKeyWindow, "QR preview leaves keyboard focus in search")
        _ = key(51)
        _ = key(35, chars: "p", mods: [.command])
        _ = key(8, chars: "c", mods: [.command])
        run(0.2)
        precondition(store.matchCount == countBeforePhone && controller.isVisible)
        precondition(store.syncDatabase.get(id: historyBeforePhone.id)?.pinned == historyBeforePhone.pinned,
                     "Delete, pin and copy on the phone card must not act on the last history selection")
        func nativeButtons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(nativeButtons)
        }
        let refreshButton = nativeButtons(phonePreview.contentView!).first { $0.accessibilityLabel() == L10n.refreshQRCode }!
        let refreshPoint = NSPoint(x: refreshButton.bounds.midX, y: refreshButton.bounds.midY)
        phonePreview.trackClick(mouse(.leftMouseDown, view: refreshButton, point: refreshPoint))
        refreshButton.performClick(nil)
        phonePreview.trackClick(mouse(.leftMouseUp, view: refreshButton, point: refreshPoint))
        run(0.2)
        precondition(pairingRevision == 123457 && controller.isPreviewVisible,
                     "Refreshing the QR code is a control action, not a paper-collapse click")
        let qrView = phonePreview.contentView!
        let qrBitmap = qrView.bitmapImageRepForCachingDisplay(in: qrView.bounds)!
        qrView.cacheDisplay(in: qrView.bounds, to: qrBitmap)
        try qrBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/phone-sync-preview.png"))
        let barcode = VNDetectBarcodesRequest()
        barcode.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: qrBitmap.cgImage!).perform([barcode])
        precondition(barcode.results?.contains { $0.payloadStringValue == pairing.address } == true,
                     "The rendered expanded paper must contain the current, scannable pairing URL")
        _ = key(53)
        run(0.06)
        _ = key(49, chars: " ")
        run(0.7)
        precondition(controller.isPreviewVisible && controller.previewSelectionID == phoneID,
                     "Space reverses the phone paper's interrupted return through the shared flight")
        _ = key(125)
        run(0.7)
        precondition(controller.previewSelectionID == controller.panelModel.current?.id && controller.isPreviewVisible)
        precondition(phoneIsland.alphaValue == 1, "Navigating back to history restores the permanent card")
        _ = key(53)
        run(0.6)
        store.query = "no-such-phone-test-record"
        run(0.6)
        precondition(controller.panelModel.current == nil && treeWindow.paper(for: phoneID) != nil)
        precondition((treeWindow.paper(for: phoneID)!.contentView as! TreePaperSurface).accessibilityPerformPress())
        run(0.6)
        precondition(controller.isPreviewVisible && controller.previewSelectionID == phoneID,
                     "Phone pairing remains available when search has no history results")
        _ = key(53)
        run(0.6)
        precondition(!controller.isPreviewVisible && !phonePreview.handlesPaperPinch && phoneIsland.alphaValue == 1)
        store.query = ""
        run(0.6)
        print("PASS: permanent phone card, stable page anchor, protected history actions, shared interruptible preview, QR refresh controls, rendered QR decoding, empty search pairing")
        print(
            "PASS: borderless transparent key window, filtered search, packaged resource, shared selection/copy/paste/pin/delete, tree-only presentation with legacy preferences, page selection, lazy loading, empty search, query reset, compact panel, OS click-through, bounded paper/search windows, drag payload round trips, paper-origin preview and interruptible return, explicit move/size mode, clean dismissal"
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
