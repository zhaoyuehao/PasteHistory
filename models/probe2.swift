import Foundation
import RealityKit

do {
    let entity = try ModelEntity.loadModel(contentsOf: URL(fileURLWithPath: "models/brass_tree.usdz"))
    let bb = entity.visualBounds(relativeTo: nil)
    let ext = bb.extents
    print(String(format: "RealityKit OK size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f)",
                 ext.x, ext.y, ext.z, bb.center.x, bb.center.y, bb.center.z))
    var meshes = 0
    entity.forEachDescendant { e in if (e as? ModelEntity)?.mesh != nil { meshes += 1 } }
    print("mesh entities=\(meshes)")
} catch {
    print("RealityKit FAILED: \(error)")
}
