import Foundation
import RealityKit

do {
    let entity = try ModelEntity.loadModel(contentsOf: URL(fileURLWithPath: "models/brass_tree.usdz"))
    let bb = entity.visualBounds(relativeTo: nil)
    let ext = bb.extents
    print(String(format: "RealityKit OK size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f)",
                 ext.x, ext.y, ext.z, bb.center.x, bb.center.y, bb.center.z))
    var meshes = 0
    var children = 0
    var stack: [Entity] = [entity]
    while let e = stack.popLast() {
        children += 1
        if e is ModelEntity { meshes += 1 }
        stack.append(contentsOf: e.children)
    }
    print("entities=\(children) modelEntities=\(meshes)")
} catch {
    print("RealityKit FAILED: \(error)")
}
