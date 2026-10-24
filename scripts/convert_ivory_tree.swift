import AppKit
import SceneKit

// Blender exports Y-up OBJ; SceneKit archives geometry only, with no external textures.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: swift convert_ivory_tree.swift input-directory output.scn") }
let scene = SCNScene()
for name in ["Tree", "Bird_01", "Bird_02", "Bird_03", "Bird_04", "Bird_05"] {
    let url = URL(fileURLWithPath: args[1]).appendingPathComponent(name + ".obj")
    let part = try SCNScene(url: url, options: [.checkConsistency: true])
    let group = SCNNode()
    group.name = name
    for node in part.rootNode.childNodes { group.addChildNode(node) }
    scene.rootNode.addChildNode(group)
}
let ivory = SCNMaterial()
ivory.lightingModel = .physicallyBased
ivory.diffuse.contents = NSColor(red: 0.92, green: 0.90, blue: 0.85, alpha: 1)
ivory.roughness.contents = 0.82
ivory.metalness.contents = 0.0
scene.rootNode.enumerateChildNodes { node, _ in
    if let geometry = node.geometry { geometry.materials = [ivory] }
}
let (lo, hi) = scene.rootNode.boundingBox
precondition(hi.y-lo.y > 8 && hi.z-lo.z > 1.5, "Missing tree height/depth")
precondition(scene.write(to: URL(fileURLWithPath: args[2]), options: nil, delegate: nil, progressHandler: nil))
print("Saved volumetric scene; bounds: \(lo) ... \(hi)")
