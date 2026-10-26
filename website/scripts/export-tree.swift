// Re-export the existing native asset; no Blender source is needed.
import AppKit
import SceneKit
import simd
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let scene = try SCNScene(url: root)
var binary = Data()
var views = [[String: Any]](), accessors = [[String: Any]](), meshes = [[String: Any]](), nodes = [[String: Any]]()
func append<T>(_ array: [T]) -> Int {
    while binary.count % 4 != 0 { binary.append(0) }
    let offset = binary.count
    array.withUnsafeBytes { binary.append(contentsOf: $0) }
    views.append(["buffer":0,"byteOffset":offset,"byteLength":binary.count-offset])
    return views.count-1
}
func vector(_ source: SCNGeometrySource, _ index: Int) -> SCNVector3 {
    source.data.withUnsafeBytes { p in
        let start = source.dataOffset + index * source.dataStride
        return SCNVector3(p.loadUnaligned(fromByteOffset:start,as:Float.self),p.loadUnaligned(fromByteOffset:start+4,as:Float.self),p.loadUnaligned(fromByteOffset:start+8,as:Float.self))
    }
}
scene.rootNode.enumerateChildNodes { node, _ in
    guard let geo = node.geometry, let pos = geo.sources(for:.vertex).first, let norm = geo.sources(for:.normal).first else { return }
    var positions = [Float](), normals = [Float](), indices = [UInt32]()
    var lo = SIMD3<Float>(repeating:Float.infinity), hi = SIMD3<Float>(repeating: -Float.infinity)
    for i in 0..<pos.vectorCount {
        let v = node.convertPosition(vector(pos,i), to:scene.rootNode)
        let n = node.convertVector(vector(norm,i), to:scene.rootNode)
        let vv = SIMD3<Float>(Float(v.x),Float(v.y),Float(v.z)), nn = simd_normalize(SIMD3<Float>(Float(n.x),Float(n.y),Float(n.z)))
        positions += [vv.x,vv.y,vv.z]; normals += [nn.x,nn.y,nn.z]
        lo = simd_min(lo,vv); hi = simd_max(hi,vv)
    }
    for e in geo.elements where e.primitiveType == .triangles {
        e.data.withUnsafeBytes { p in
            for i in 0..<(e.primitiveCount*3) {
                let at = i * e.bytesPerIndex
                if e.bytesPerIndex == 4 { indices.append(p.loadUnaligned(fromByteOffset:at,as:UInt32.self)) }
                else if e.bytesPerIndex == 2 { indices.append(UInt32(p.loadUnaligned(fromByteOffset:at,as:UInt16.self))) }
                else { indices.append(UInt32(p[at])) }
            }
        }
    }
    let pa = accessors.count
    accessors.append(["bufferView":append(positions),"componentType":5126,"count":pos.vectorCount,"type":"VEC3","min":[lo.x,lo.y,lo.z],"max":[hi.x,hi.y,hi.z]])
    accessors.append(["bufferView":append(normals),"componentType":5126,"count":pos.vectorCount,"type":"VEC3"])
    accessors.append(["bufferView":append(indices),"componentType":5125,"count":indices.count,"type":"SCALAR"])
    meshes.append(["name":node.name ?? "Ivory","primitives":[["attributes":["POSITION":pa,"NORMAL":pa+1],"indices":pa+2,"material":0]]])
    nodes.append(["name":node.name ?? "Ivory","mesh":meshes.count-1])
}
let document: [String:Any] = ["asset":["version":"2.0","generator":"PasteHistory native mesh export"],"scene":0,"scenes":[["nodes":Array(nodes.indices)]],"nodes":nodes,"meshes":meshes,"materials":[["name":"Ivory porcelain","pbrMetallicRoughness":["baseColorFactor":[0.92,0.90,0.83,1.0],"metallicFactor":0,"roughnessFactor":0.63],"doubleSided":true]],"buffers":[["byteLength":binary.count]],"bufferViews":views,"accessors":accessors]
var json = try JSONSerialization.data(withJSONObject: document, options:[.sortedKeys])
while json.count % 4 != 0 { json.append(32) }
while binary.count % 4 != 0 { binary.append(0) }
var glb = Data()
func word(_ n:UInt32) { var le = n.littleEndian; withUnsafeBytes(of:&le) { glb.append(contentsOf:$0) } }
word(0x46546c67); word(2); word(UInt32(12+8+json.count+8+binary.count)); word(UInt32(json.count)); word(0x4e4f534a); glb.append(json); word(UInt32(binary.count)); word(0x004e4942); glb.append(binary)
try glb.write(to:output.appendingPathComponent("tree.glb"))
// Matching transparent fallback rendered from the same geometry.
let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.fieldOfView = 38
camera.position = SCNVector3(0,4.15,16.5); scene.rootNode.addChildNode(camera)
for (type, intensity, position) in [(SCNLight.LightType.directional,CGFloat(850),SCNVector3(-5,10,8)),(.ambient,CGFloat(400),SCNVector3(0,0,0))] {
 let light = SCNNode(); light.light = SCNLight(); light.light!.type = type; light.light!.intensity = intensity; light.position = position; if type == .directional {light.look(at:SCNVector3(0,4,0))}; scene.rootNode.addChildNode(light)
}
let renderer = SCNRenderer(device:nil, options:nil); renderer.scene = scene; renderer.pointOfView = camera; scene.background.contents = NSColor.clear
let shot = renderer.snapshot(atTime:0, with:CGSize(width:800,height:1100), antialiasingMode:.multisampling4X)
if let tiff = shot.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) { try png.write(to:output.appendingPathComponent("tree-fallback.png")) }
print("Exported \(meshes.count) meshes, \(glb.count) bytes")
