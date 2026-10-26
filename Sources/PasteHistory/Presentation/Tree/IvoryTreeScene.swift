import AppKit
import SceneKit

enum IvoryTreeLayout {
    static let pageSize = 8
    static let cardWidth: CGFloat = 158
    static let cardHeight: CGFloat = 74
    static let selectedHeight: CGFloat = 112
    static let imageCardHeight: CGFloat = 98
    static let selectedImageHeight: CGFloat = 128
}

struct IvoryTreeEntry: Equatable {
    enum Kind { case clip, phoneSync }
    static let phoneSyncID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static var phoneSync: Self {
        Self(kind: .phoneSync, id: phoneSyncID, title: L10n.phoneSync, index: -1)
    }
    var kind: Kind = .clip
    var isPermanent: Bool { kind == .phoneSync }
    let id: UUID
    let title: String
    let index: Int
    var source: String = ""
    var date: String = ""
    var pinned: Bool = false
    var thumbnail: Data? = nil
    var imageFirst: Bool = false
}

/// The sculpture is native geometry. Readable paper billboards follow actual mesh
/// attachment points; their cords are projected from those same points every frame.
final class IvoryTreeSceneView: SCNView {
    private let pivot = SCNNode()
    private let sculpture = SCNNode()
    private let cameraNode = SCNNode()
    private let paper = IvoryTreePaperView()
    private var anchors: [SCNVector3] = []
    private var entries: [IvoryTreeEntry] = []
    private var selectedID: UUID?
    private var timer: Timer?
    private var yaw: CGFloat = -0.24
    private var pitch: CGFloat = -0.04
    private var targetYaw: CGFloat = -0.24
    private var targetPitch: CGFloat = -0.04
    private var yawVelocity: CGFloat = 0
    private var pitchVelocity: CGFloat = 0
    private var sway: CGFloat = 0
    private var lastStep: CFTimeInterval = 0
    var onSelect: ((UUID) -> Void)?
    var onPreview: ((UUID) -> Void)?
    var layoutEditing = false { didSet { paper.layoutEditing = layoutEditing; startSettling() } }
    var onRootPosition: ((CGPoint) -> Void)?
    private(set) var loadError: Error?
    var cardFrames: [UUID: NSRect] { paper.cardFrames }
    var isTurningPage: Bool { paper.isTurningPage }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(url: URL?) {
        super.init(frame: .zero, options: nil)
        let scene = SCNScene()
        self.scene = scene
        backgroundColor = .clear
        scene.background.contents = NSColor.clear
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        autoenablesDefaultLighting = false
        scene.rootNode.addChildNode(pivot)
        pivot.position.y = 4.4
        sculpture.position.y = -4.4
        pivot.addChildNode(sculpture)
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            let asset = try SCNScene(url: url, options: [.checkConsistency: true])
            anchors = Self.surfaceAnchors(in: asset)
            for node in asset.rootNode.childNodes { sculpture.addChildNode(node) }
        } catch { loadError = error }
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
        addSubview(paper)
        paper.autoresizingMask = [.width, .height]
        paper.onSelect = { [weak self] id in self?.onSelect?(id) }
        paper.onPreview = { [weak self] id in self?.onPreview?(id) }
        applyRotation()
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }

    private func addLight(
        type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3, shadows: Bool = false
    ) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.intensity = intensity
        node.light?.color = NSColor(white: 1, alpha: 1)
        node.light?.castsShadow = shadows
        node.light?.shadowRadius = 5
        node.light?.shadowSampleCount = 16
        node.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        node.light?.shadowColor = NSColor(white: 0, alpha: 0.35)
        node.light?.orthographicScale = 12
        node.position = position
        if type == .directional { node.look(at: SCNVector3(0, 4, 0)) }
        scene?.rootNode.addChildNode(node)
    }
    override func layout() {
        super.layout()
        paper.frame = bounds
        let aspect = max(0.2, bounds.width / max(bounds.height, 1))
        let distance = max(5.25 / tan(19 * .pi / 180), 4.1 / (tan(19 * .pi / 180) * aspect))
        cameraNode.position = SCNVector3(0, 4.15, distance)
        updatePaper(dt: 1.0 / 60)
        startSettling()
    }

    // These are only search seeds. The final attachments are vertices on the
    // imported tree surface, so export/deformation changes cannot leave cords floating.
    private static let seeds: [(Double, Double)] = [
        (-0.78, 7.75), (1.37, 7.02), (1.92, 6.05), (-2.04, 5.58), (2.03, 3.60), (-2.32, 2.77),
        (2.16, 1.98), (-1.70, 1.25), (-2.9, 7.2),
    ]
    static func anchor(_ slot: Int) -> SCNVector3 {
        let (x, y) = seeds[slot % seeds.count]
        let depth = 0.42 * x * sin(y * 1.1) + 0.35 * (sin(x * 1.7 + y * 0.2) - sin(y * 0.2))
        return SCNVector3(x, y, -depth)
    }
    private static func surfaceAnchors(in asset: SCNScene) -> [SCNVector3] {
        let seeds = (0...IvoryTreeLayout.pageSize).map(anchor)
        var found = seeds
        var distances = Array(repeating: CGFloat.greatestFiniteMagnitude, count: seeds.count)
        asset.rootNode.childNode(withName: "Tree", recursively: true)?.enumerateChildNodes { node, _ in
            guard let source = node.geometry?.sources(for: .vertex).first, source.usesFloatComponents,
                source.bytesPerComponent == 4
            else { return }
            source.data.withUnsafeBytes { bytes in
                for i in 0..<source.vectorCount {
                    let start = source.dataOffset + i * source.dataStride
                    let x = bytes.loadUnaligned(fromByteOffset: start, as: Float.self)
                    let y = bytes.loadUnaligned(fromByteOffset: start + 4, as: Float.self)
                    let z = bytes.loadUnaligned(fromByteOffset: start + 8, as: Float.self)
                    let p = node.convertPosition(SCNVector3(x, y, z), to: asset.rootNode)
                    for j in seeds.indices {
                        let d = seeds[j]
                        let dx = p.x - d.x
                        let dy = p.y - d.y
                        let dz = p.z - d.z
                        let distance = dx * dx + dy * dy + dz * dz * 0.2
                        if distance < distances[j] {
                            distances[j] = distance
                            found[j] = p
                        }
                    }
                }
            }
        }
        return found
    }
    func attachmentPosition(_ slot: Int) -> SCNVector3 {
        sculpture.convertPosition(
            anchors.isEmpty ? Self.anchor(slot) : anchors[slot % anchors.count], to: nil)
    }
    func update(entries: [IvoryTreeEntry], selectedID: UUID?) {
        let changed = self.entries != entries
        self.entries = entries
        self.selectedID = selectedID
        paper.update(entries: entries, selectedID: selectedID, turnPage: changed)
        updatePaper(dt: 1.0 / 60)
        startSettling()
    }
    func present() {
        paper.finishEntrance()
        startSettling()
    }
    private func updatePaper(dt: CGFloat) {
        let attachments = entries.indices.map { slot -> IvoryTreePaperView.Attachment in
            let world = attachmentPosition(entries[slot].isPermanent ? IvoryTreeLayout.pageSize : slot)
            let p = projectPoint(world)
            return .init(point: NSPoint(x: p.x, y: bounds.height - p.y), height: world.y, depth: world.z)
        }
        paper.advance(attachments: attachments, sway: sway, dt: dt)
        let root = projectPoint(sculpture.convertPosition(SCNVector3(0, 0.25, 0), to: nil))
        onRootPosition?(CGPoint(x: root.x, y: bounds.height - root.y))
    }
    // Display-only. Pointer gestures belong to paper windows or the layout handle.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    static func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        guard let available = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, available.minX), max(available.minX, available.maxX - size.width)),
            y: min(max(origin.y, available.minY), max(available.minY, available.maxY - size.height)))
    }
    func entryID(at point: NSPoint) -> UUID? {
        paper.entryID(at: NSPoint(x: point.x, y: bounds.height - point.y))
    }
    func resetView() {
        // Take the shortest path home even after several full revolutions.
        let turns = ((yaw + 0.24) / (2 * .pi)).rounded()
        yaw -= turns * 2 * .pi
        targetYaw = -0.24
        targetPitch = -0.04
        startSettling()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRendering() } else { present() }
    }
    func stopRendering() {
        timer?.invalidate()
        timer = nil
    }
    private func applyRotation() {
        let rotation = SCNVector3(pitch, yaw, 0)
        guard pivot.eulerAngles.x != rotation.x || pivot.eulerAngles.y != rotation.y else { return }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        pivot.eulerAngles = rotation
        SCNTransaction.commit()
    }
    private func startSettling() {
        guard timer == nil else { return }
        lastStep = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func step() {
        guard window?.isVisible == true else {
            stopRendering()
            return
        }
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(1.0 / 30, max(1.0 / 240, now - lastStep)))
        lastStep = now
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let steps = dt * 60
        let damping = pow(0.71, steps)
        func advance(_ value: inout CGFloat, _ velocity: inout CGFloat, _ target: CGFloat) {
            velocity = (velocity + (target - value) * 0.18 * steps) * damping
            value += reduced ? target - value : velocity * steps
        }
        advance(&yaw, &yawVelocity, targetYaw)
        advance(&pitch, &pitchVelocity, targetPitch)
        sway = reduced ? 0 : (sway - yawVelocity * 28) * pow(0.84, steps)
        applyRotation()
        updatePaper(dt: dt)
        let error =
            abs(yaw - targetYaw) + abs(pitch - targetPitch) + abs(yawVelocity) + abs(pitchVelocity)
            + abs(sway)
        if error < 0.0001 && !paper.isAnimating { stopRendering() }
    }
}
