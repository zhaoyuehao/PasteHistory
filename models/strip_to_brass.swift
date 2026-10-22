import Foundation
import AppKit
import SceneKit

// 加载完整 USDZ（含贴图），换材质后导出 .scn：贴图引用被替换掉，导出自动瘦身
guard let scene = try? SCNScene(url: URL(fileURLWithPath: "models/brass_tree.usdz"), options: nil) else {
    print("SCNScene FAILED to load usdz"); exit(1)
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
    geo.materials = Array(repeating: brass, count: geo.materials.count)
}

let (bbMin, bbMax) = scene.rootNode.boundingBox
print(String(format: "meshes=%d bbox=(%.2f,%.2f,%.2f)...(%.2f,%.2f,%.2f)",
             meshCount, bbMin.x, bbMin.y, bbMin.z, bbMax.x, bbMax.y, bbMax.z))

let out = URL(fileURLWithPath: "models/brass_tree.scn")
try? FileManager.default.removeItem(at: out)
scene.write(to: out, options: nil, delegate: nil, progressHandler: nil)

let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
print("exported brass_tree.scn size=\(size)")

// 复验：从 .scn 再载入一次（app 里的加载路径）
if let verify = SCNScene(named: "models/brass_tree.scn") {
    var nodes = 0
    verify.rootNode.enumerateHierarchy { _, _ in nodes += 1 }
    print("verify: nodes=\(nodes) ok")
} else {
    print("verify FAILED")
}
