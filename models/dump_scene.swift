import Foundation
import SceneKit

func dump(_ node: SCNNode, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    let geo = node.geometry != nil ? " GEO" : ""
    print("\(indent)\(node.name ?? "?")\(geo) children=\(node.childNodes.count)")
    if depth < 6 {
        for c in node.childNodes { dump(c, depth: depth + 1) }
    }
}

for path in ["models/brass_tree.usdz", "models/brass_tree_extracted/output.usdc"] {
    print("=== \(path)")
    if let scene = try? SCNScene(url: URL(fileURLWithPath: path), options: nil) {
        dump(scene.rootNode, depth: 0)
        let (lo, hi) = scene.rootNode.boundingBox
        print(String(format: "bbox=(%.2f,%.2f,%.2f)...(%.2f,%.2f,%.2f)", lo.x, lo.y, lo.z, hi.x, hi.y, hi.z))
    } else {
        print("load FAILED")
    }
}
