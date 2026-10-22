import SceneKit
import ModelIO
import RealityKit

// 1) SCNNode(mdlMesh:) 可用性
let probe1 = SCNNode(mdlMesh: MDLMesh())
print("SCNNode(mdlMesh:) OK")

// 2) RealityKit 能否加载 Hunyuan USDZ
do {
    let entity = try ModelEntity.loadModel(contentsOf: URL(fileURLWithPath: "models/brass_tree.usdz"))
    let bb = entity.visualBounds
    print("RealityKit OK bounds=\(bb.extents)")
} catch {
    print("RealityKit FAILED: \(error)")
}
