import AppKit
import SwiftUI

/// The sculpture window never receives mouse events. Only these small, visible
/// paper/control windows participate in macOS hit testing; no event replay/tap.
final class TreeInteractionPanel: NSPanel {
    enum Role { case paper, search, layout }
    let role: Role
    weak var owner: HistoryPanel?
    private var localPin: NSPoint?
    var paperPin: NSPoint? {
        get { localPin.map { convertPoint(toScreen: $0) } }
        set { localPin = newValue.map { convertPoint(fromScreen: $0) } }
    }
    var paperSize: NSSize = .zero
    var paperAngle: CGFloat = 0
    var paperColor = IvoryPaperStyle.fill
    var paperSnapshot: (() -> NSImage?)?
    var paperPose: PaperPose? {
        paperPin.map { PaperPose(pin: $0, size: paperSize, angle: paperAngle, padding: 3) }
    }
    var enabled = true { didSet { ignoresMouseEvents = !enabled } }
    override var canBecomeKey: Bool { role != .paper }
    override var canBecomeMain: Bool { false }
    init(owner: HistoryPanel, role: Role) {
        self.owner = owner
        self.role = role
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = role == .paper
        isReleasedWhenClosed = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = owner.level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        owner.register(self)
    }
    func detach() {
        owner?.unregister(self)
        orderOut(nil)
    }
}

/// Portals render the search/layout controls in a bounded input window, rather
/// than making the entire transparent SwiftUI hosting window intercept clicks.
struct TreeControlPortal<Content: View>: NSViewRepresentable {
    let role: TreeInteractionPanel.Role
    let content: Content
    init(role: TreeInteractionPanel.Role, @ViewBuilder content: () -> Content) {
        self.role = role; self.content = content()
    }
    func makeNSView(context: Context) -> TreeControlPortalView<Content> {
        TreeControlPortalView(role: role, content: content)
    }
    func updateNSView(_ view: TreeControlPortalView<Content>, context: Context) {
        view.host.rootView = content
        view.synchronize()
    }
    static func dismantleNSView(_ view: TreeControlPortalView<Content>, coordinator: ()) { view.detach() }
}
final class TreeControlPortalView<Content: View>: NSView {
    let host: NSHostingView<Content>
    let role: TreeInteractionPanel.Role
    private var island: TreeInteractionPanel?
    init(role: TreeInteractionPanel.Role, content: Content) {
        self.role = role
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        host.safeAreaRegions = []
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronize() }
    override func layout() { super.layout(); synchronize() }
    func synchronize() {
        guard let owner = window as? HistoryPanel else { detach(); return }
        if island?.owner !== owner {
            detach()
            let panel = TreeInteractionPanel(owner: owner, role: role)
            panel.contentView = host
            panel.title = role == .search ? "搜索剪贴记录" : "调整树布局"
            island = panel
        }
        guard bounds.width > 0, bounds.height > 0, let island else { return }
        let rect = owner.convertToScreen(convert(bounds, to: nil))
        if island.frame != rect { island.setFrame(rect, display: true) }
        owner.showIslandIfNeeded(island)
        if role == .search, owner.isVisible, NSApp.keyWindow === owner {
            DispatchQueue.main.async { [weak owner] in owner?.focusSearch() }
        } else if role == .layout, owner.isVisible, owner.layoutEditing, NSApp.keyWindow === owner {
            DispatchQueue.main.async { [weak island, weak owner] in
                guard owner?.layoutEditing == true, island?.isVisible == true else { return }
                island?.makeKey()
            }
        }
    }
    func detach() { island?.detach(); island = nil }
}

/// The only surface that moves the sculpture; available only in layout mode.
struct TreeMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> TreeMoveHandleView { TreeMoveHandleView() }
    func updateNSView(_ view: TreeMoveHandleView, context: Context) {}
}
final class TreeMoveHandleView: NSView {
    private var start = NSPoint.zero
    private var origin = NSPoint.zero
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        let text = "⠿ 移动" as NSString
        text.draw(at: NSPoint(x: 7, y: 7), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor])
    }
    override func mouseDown(with event: NSEvent) {
        guard let owner = (window as? TreeInteractionPanel)?.owner, owner.layoutEditing else { return }
        start = window!.convertPoint(toScreen: event.locationInWindow)
        origin = owner.frame.origin
        NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let owner = (window as? TreeInteractionPanel)?.owner, owner.layoutEditing else { return }
        let point = window!.convertPoint(toScreen: event.locationInWindow)
        let proposed = NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)
        owner.setFrameOrigin(IvoryTreeSceneView.clampedOrigin(proposed, size: owner.frame.size))
    }
    override func mouseUp(with event: NSEvent) { NSCursor.openHand.set() }
}
