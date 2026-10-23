import Foundation
import ModelIO
import SceneKit

let path = "models/brass_tree_extracted/output.usdc"
let asset = MDLAsset(url: URL(fileURLWithPath: path))
print("asset objects=\(asset.count)")

var meshes: [MDLMesh] = []
func walk(_ o: MDLObject) {
    if let m = o as? MDLMesh { meshes.append(m) }
    for c in o.children.objects { walk(c) }
}
for i in 0..<asset.count { walk(asset.object(at: i)) }

print("MDLMesh count=\(meshes.count)")
var verts = 0, tris = 0
for m in meshes {
    verts += m.vertexCount
    for sm in m.submeshes?.compactMap({ $0 as? MDLSubmesh }) ?? [] { tris += sm.indexCount / 3 }
}
print("verts=\(verts) tris=\(tris)")

if let bb = meshes.first?.boundingBox {
    print(String(format: "mesh0 bbox=(%.3f,%.3f,%.3f)...(%.3f,%.3f,%.3f)",
                 bb.minBounds.x, bb.minBounds.y, bb.minBounds.z,
                 bb.maxBounds.x, bb.maxBounds.y, bb.maxBounds.z))
}

// 桥接到 SceneKit 并导出
let scene = SCNScene()
let brass = SCNMaterial()
brass.lightingModel = .physicallyBased
brass.diffuse.contents = NSColor(red: 0.72, green: 0.55, blue: 0.33, alpha: 1)
brass.metalness.contents = 1.0
brass.roughness.contents = 0.36

for m in meshes {
    let node = SCNNode(mdlMesh: m)
    node.geometry?.materials = Array(repeating: brass, count: node.geometry?.materials.count ?? 0)
    // ModelIO 坐标系不确定（USD 是 z-up）：先原样导出，包围盒在 SceneKit 侧再标定
    scene.rootNode.addChildNode(node)
}
let out = URL(fileURLWithPath: "models/brass_tree.scn")
try? FileManager.default.removeItem(at: out)
scene.write(to: out, options: nil, delegate: nil, progressHandler: nil)
let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
print("exported scn size=\(size)")

if let verify = try? SCNScene(url: out, options: nil) {
    let (lo, hi) = verify.rootNode.boundingBox
    print(String(format: "verify bbox=(%.2f,%.2f,%.2f)...(%.2f,%.2f,%.2f)", lo.x, lo.y, lo.z, hi.x, hi.y, hi.z))
} else {
    print("verify FAILED")
}
