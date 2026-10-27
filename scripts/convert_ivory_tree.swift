import AppKit
import SceneKit

// Blender exports Y-up OBJ; SceneKit archives geometry and the small material palette,
// with no external textures.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: swift convert_ivory_tree.swift input-directory output.scn") }
let scene = SCNScene()
let bodyParts = ["Tree", "Bird_01", "Bird_02", "Bird_03", "Bird_04", "Bird_05"]
var groups: [String: SCNNode] = [:]
for name in bodyParts {
    let url = URL(fileURLWithPath: args[1]).appendingPathComponent(name + ".obj")
    let part = try SCNScene(url: url, options: [.checkConsistency: true])
    let group = SCNNode()
    group.name = name
    for node in part.rootNode.childNodes { group.addChildNode(node) }
    scene.rootNode.addChildNode(group)
    groups[name] = group
}
for name in ["Bird_01_accent", "Bird_02_accent", "Bird_03_accent", "Bird_04_accent", "Bird_05_accent"] {
    let url = URL(fileURLWithPath: args[1]).appendingPathComponent(name + ".obj")
    let part = try SCNScene(url: url, options: [.checkConsistency: true])
    for node in part.rootNode.childNodes { groups[name.replacingOccurrences(of: "_accent", with: "")]?.addChildNode(node) }
}
func material(_ color: NSColor, roughness: CGFloat) -> SCNMaterial {
    let result = SCNMaterial()
    result.lightingModel = .physicallyBased
    result.diffuse.contents = color
    result.roughness.contents = roughness
    result.metalness.contents = 0.0
    return result
}
let treeMaterial = material(NSColor(red: 0.86, green: 0.82, blue: 0.73, alpha: 1), roughness: 0.74)
let birdMaterial = material(NSColor(red: 0.31, green: 0.37, blue: 0.39, alpha: 1), roughness: 0.58)
let accentMaterial = material(NSColor(red: 0.72, green: 0.42, blue: 0.16, alpha: 1), roughness: 0.48)
scene.rootNode.enumerateChildNodes { node, _ in
    guard let geometry = node.geometry, let name = node.name else { return }
    if name == "Tree" { geometry.materials = [treeMaterial] }
    else if name.hasSuffix("_accent") { geometry.materials = [accentMaterial] }
    else if name.hasPrefix("Bird_") { geometry.materials = [birdMaterial] }
}
let (lo, hi) = scene.rootNode.boundingBox
precondition(hi.y-lo.y > 8 && hi.z-lo.z > 1.5, "Missing tree height/depth")
precondition(scene.write(to: URL(fileURLWithPath: args[2]), options: nil, delegate: nil, progressHandler: nil))
print("Saved volumetric scene; bounds: \(lo) ... \(hi)")
