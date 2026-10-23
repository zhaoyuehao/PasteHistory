import Foundation
import AppKit
import SceneKit

guard let scene = try? SCNScene(url: URL(fileURLWithPath: "obj_extracted/07e04659e8ff5dca3359f450afc3ac46.obj"), options: nil) else {
    print("OBJ load FAILED"); exit(1)
}

let brass = SCNMaterial()
brass.lightingModel = .physicallyBased
brass.diffuse.contents = NSColor(red: 0.72, green: 0.55, blue: 0.33, alpha: 1)
brass.metalness.contents = 1.0
brass.roughness.contents = 0.36

var meshCount = 0
scene.rootNode.enumerateHierarchy { node, _ in
    guard let geo = node.geometry else { return }
    meshCount += 1
    geo.materials = Array(repeating: brass, count: max(geo.materials.count, 1))
}
let (lo, hi) = scene.rootNode.boundingBox
print(String(format: "meshes=%d bbox=(%.2f,%.2f,%.2f)...(%.2f,%.2f,%.2f)",
             meshCount, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z))

let out = URL(fileURLWithPath: "brass_tree.scn")
try? FileManager.default.removeItem(at: out)
scene.write(to: out, options: nil, delegate: nil, progressHandler: nil)
let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
print("exported scn size=\(size)")

if let verify = try? SCNScene(url: out, options: nil) {
    let (vlo, vhi) = verify.rootNode.boundingBox
    print(String(format: "verify bbox=(%.2f,%.2f,%.2f)...(%.2f,%.2f,%.2f)", vlo.x, vlo.y, vlo.z, vhi.x, vhi.y, vhi.z))
} else {
    print("verify FAILED")
}
