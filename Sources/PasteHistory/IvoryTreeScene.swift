import AppKit
import SceneKit

struct IvoryTreeEntry: Equatable {
    let id: UUID
    let title: String
    let index: Int
}

/// Native geometry, perspective projection and hit testing; no rendered tree image.
final class IvoryTreeSceneView: SCNView {
    private let pivot = SCNNode()
    private let tags = SCNNode()
    private let cameraNode = SCNNode()
    private let selectionNode = SCNNode()
    private var entries: [IvoryTreeEntry] = []
    private var selectedID: UUID?
    private var positions: [UUID: SCNVector3] = [:]
    private var timer: Timer?
    private var yaw: CGFloat = -0.24
    private var pitch: CGFloat = -0.04
    private var targetYaw: CGFloat = -0.24
    private var targetPitch: CGFloat = -0.04
    private var yawVelocity: CGFloat = 0.0
    private var pitchVelocity: CGFloat = 0.0
    private var selectionTarget = SCNVector3Zero
    private var selectionVelocity = SCNVector3Zero
    private var downPoint = NSPoint.zero
    private var previousPoint = NSPoint.zero
    private var dragged = false
    var onSelect: ((UUID) -> Void)?
    var onActivate: ((UUID) -> Void)?
    private(set) var loadError: Error?
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    init(url: URL?) {
        super.init(frame: .zero, options: nil)
        let scene = SCNScene()
        self.scene = scene
        backgroundColor = NSColor(red: 0.095, green: 0.105, blue: 0.12, alpha: 1)
        antialiasingMode = .multisampling8X
        preferredFramesPerSecond = 60
        autoenablesDefaultLighting = false
        scene.rootNode.addChildNode(pivot)
        pivot.position.y = 4.4
        let sculpture = SCNNode()
        sculpture.position.y = -4.4
        pivot.addChildNode(sculpture)
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            let asset = try SCNScene(url: url, options: [.checkConsistency: true])
            for node in asset.rootNode.childNodes { sculpture.addChildNode(node) }
        } catch { loadError = error }
        sculpture.addChildNode(tags)
        sculpture.addChildNode(selectionNode)
        let frame = SCNBox(width: 1.20, height: 0.62, length: 0.045, chamferRadius: 0.065)
        let accent = SCNMaterial()
        accent.diffuse.contents = NSColor(red: 0.35, green: 0.69, blue: 0.8, alpha: 1)
        accent.emission.contents = NSColor(red: 0.08, green: 0.22, blue: 0.27, alpha: 1)
        frame.materials = [accent]
        selectionNode.geometry = frame
        selectionNode.isHidden = true
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 38
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.camera?.wantsHDR = false
        cameraNode.camera?.screenSpaceAmbientOcclusionIntensity = 1.1
        cameraNode.camera?.screenSpaceAmbientOcclusionRadius = 0.3
        scene.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        addLight(type: .directional, intensity: 850, position: SCNVector3(-5, 10, 8), shadows: true)
        addLight(type: .omni, intensity: 220, position: SCNVector3(5, 5, -3))
        addLight(type: .ambient, intensity: 230, position: .init())
        let wall = SCNNode(geometry: SCNPlane(width: 40, height: 40))
        wall.position = SCNVector3(0, 4, -3)
        let wallMaterial = SCNMaterial()
        wallMaterial.diffuse.contents = NSColor(white: 0.12, alpha: 1)
        wallMaterial.roughness.contents = 1.0
        wall.geometry?.materials = [wallMaterial]
        scene.rootNode.addChildNode(wall)
        applyRotation()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }

    private func addLight(type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3, shadows: Bool = false) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.intensity = intensity
        node.light?.color = NSColor(white: 1, alpha: 1)
        node.light?.castsShadow = shadows
        node.light?.shadowRadius = 5
        node.light?.shadowSampleCount = 16
        node.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        node.light?.shadowColor = NSColor(white: 0, alpha: 0.4)
        node.light?.orthographicScale = 12
        node.position = position
        if type == .directional { node.look(at: SCNVector3(0, 4, 0)) }
        scene?.rootNode.addChildNode(node)
    }

    override func layout() {
        super.layout()
        let aspect = max(0.2, bounds.width / max(bounds.height, 1))
        let distance = max(5.1 / tan(19 * .pi / 180), 4.2 / (tan(19 * .pi / 180) * aspect)) + 1.5
        cameraNode.position = SCNVector3(0, 4.4, distance)
    }

    // Branch coordinates match the Blender exporter. Y becomes vertical, -depth becomes Z.
    private static let anchors: [(Double, Double)] = [(-1.70, 1.25), (2.16, 1.98), (-2.32, 2.77), (2.03, 3.60), (-2.04, 5.58), (1.92, 6.05)]
    static func anchor(_ slot: Int) -> SCNVector3 {
        let (x, y) = anchors[slot % anchors.count]
        let depth = 0.42*x*sin(y*1.1)+0.35*(sin(x*1.7+y*0.2)-sin(y*0.2))
        return SCNVector3(x, y, -depth + 0.2)
    }

    func update(entries: [IvoryTreeEntry], selectedID: UUID?) {
        if self.entries != entries {
            self.entries = entries
            tags.childNodes.forEach { $0.removeFromParentNode() }
            positions.removeAll()
            for (slot, entry) in entries.enumerated() {
                let anchor = Self.anchor(slot)
                let container = SCNNode()
                container.name = entry.id.uuidString
                container.position = SCNVector3(anchor.x, anchor.y - 0.55, anchor.z)
                positions[entry.id] = container.position
                let card = SCNBox(width: 1.10, height: 0.52, length: 0.07, chamferRadius: 0.045)
                let material = SCNMaterial()
                material.diffuse.contents = Self.labelImage(entry)
                material.roughness.contents = 0.85
                card.materials = [material]
                container.geometry = card
                tags.addChildNode(container)
                let cord = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.32))
                cord.position = SCNVector3(0, 0.40, 0)
                cord.geometry?.firstMaterial?.diffuse.contents = NSColor(white: 0.68, alpha: 1)
                container.addChildNode(cord)
            }
        }
        let changedSelection = self.selectedID != selectedID
        self.selectedID = selectedID
        if let selectedID, let position = positions[selectedID] {
            selectionTarget = SCNVector3(position.x, position.y, position.z - 0.045)
            if selectionNode.isHidden { selectionNode.position = selectionTarget }
            selectionNode.isHidden = false
            if changedSelection && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                selectionNode.position = selectionTarget
                selectionVelocity = SCNVector3Zero
                selectionNode.opacity = 0
                selectionNode.runAction(.fadeIn(duration: 0.15), forKey: "selectionFade")
            }
            startSettling()
        } else { selectionNode.isHidden = true }
    }

    private static func labelImage(_ entry: IvoryTreeEntry) -> NSImage {
        let image = NSImage(size: NSSize(width: 440, height: 208))
        image.lockFocus()
        NSColor(red: 0.83, green: 0.79, blue: 0.69, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 440, height: 208).fill()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (String(entry.index + 1) as NSString).draw(at: NSPoint(x: 26, y: 139), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 29, weight: .medium), .foregroundColor: NSColor.darkGray])
        (String(entry.title.prefix(40)) as NSString).draw(in: NSRect(x: 26, y: 25, width: 388, height: 95), withAttributes: [.font: NSFont.systemFont(ofSize: 35, weight: .medium), .foregroundColor: NSColor(white: 0.15, alpha: 1), .paragraphStyle: style])
        image.unlockFocus()
        return image
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        previousPoint = downPoint
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x-downPoint.x, point.y-downPoint.y) > 4 { dragged = true }
        targetYaw = min(1.15, max(-1.15, targetYaw + (point.x-previousPoint.x)*0.009))
        targetPitch = min(0.28, max(-0.28, targetPitch - (point.y-previousPoint.y)*0.006))
        previousPoint = point
        startSettling()
    }
    override func mouseUp(with event: NSEvent) {
        guard !dragged else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let id = entryID(at: point) {
            onSelect?(id)
            if event.clickCount == 2 { onActivate?(id) }
        }
    }
    func entryID(at point: NSPoint) -> UUID? {
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, let id = UUID(uuidString: name), positions[id] != nil { return id }
                node = current.parent
            }
        }
        return nil
    }
    func resetView() {
        targetYaw = -0.24; targetPitch = -0.04
        startSettling()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRendering() }
    }
    func stopRendering() { timer?.invalidate(); timer = nil }
    private func applyRotation() { pivot.eulerAngles = SCNVector3(pitch, yaw, 0) }
    private func startSettling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.step() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func step() {
        guard window?.isVisible == true else { stopRendering(); return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let damping: CGFloat = reduced ? 0.0 : 0.71
        func advance(_ value: inout CGFloat, _ velocity: inout CGFloat, _ target: CGFloat) {
            velocity = (velocity + (target-value)*0.18)*damping
            value += reduced ? (target-value)*0.5 : velocity
        }
        advance(&yaw, &yawVelocity, targetYaw)
        advance(&pitch, &pitchVelocity, targetPitch)
        applyRotation()
        var p = selectionNode.position
        advance(&p.x, &selectionVelocity.x, selectionTarget.x)
        advance(&p.y, &selectionVelocity.y, selectionTarget.y)
        advance(&p.z, &selectionVelocity.z, selectionTarget.z)
        selectionNode.position = p
        let error = abs(yaw-targetYaw)+abs(pitch-targetPitch)+abs(p.x-selectionTarget.x)+abs(p.y-selectionTarget.y)+abs(p.z-selectionTarget.z)
        let speed = abs(yawVelocity)+abs(pitchVelocity)+abs(selectionVelocity.x)+abs(selectionVelocity.y)+abs(selectionVelocity.z)
        if error+speed < 0.0001 { stopRendering() }
    }
}
