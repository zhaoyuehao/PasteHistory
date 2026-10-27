// SceneKit reference export for the web. Values mirror IvoryTreeScene.swift.
// Run only when native model / camera / lighting changes; not a UI regression test.
import AppKit
import SceneKit
let scene = try SCNScene(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let pivot = SCNNode(), sculpture = SCNNode()
let originals = scene.rootNode.childNodes
let seeds: [(Double,Double)] = [(-0.78,7.75),(1.37,7.02),(1.92,6.05),(-2.04,5.58),(2.03,3.6),(-2.32,2.77),(2.16,1.98),(-1.7,1.25),(-2.9,7.2)]
var anchors = seeds.map { x,y in SCNVector3(x,y,-(0.42*x*sin(y*1.1)+0.35*(sin(x*1.7+y*0.2)-sin(y*0.2)))) }
var distances = Array(repeating: CGFloat.greatestFiniteMagnitude, count: anchors.count)
scene.rootNode.childNode(withName:"Tree", recursively:true)?.enumerateChildNodes { node,_ in
 guard let source = node.geometry?.sources(for:.vertex).first else { return }
 source.data.withUnsafeBytes { bytes in
  for i in 0..<source.vectorCount {
   let at = source.dataOffset+i*source.dataStride
   let p = node.convertPosition(SCNVector3(bytes.loadUnaligned(fromByteOffset:at,as:Float.self),bytes.loadUnaligned(fromByteOffset:at+4,as:Float.self),bytes.loadUnaligned(fromByteOffset:at+8,as:Float.self)),to:scene.rootNode)
   for j in seeds.indices {
    let (x,y) = seeds[j], z = -(0.42*x*sin(y*1.1)+0.35*(sin(x*1.7+y*0.2)-sin(y*0.2)))
    let dx = p.x-CGFloat(x),dy = p.y-CGFloat(y),dz = p.z-CGFloat(z)
    let d = dx*dx+dy*dy+dz*dz*0.2
    if d < distances[j] { distances[j] = d; anchors[j] = p }
   }
  }
 }
}
pivot.position.y = 4.4; sculpture.position.y = -4.4
scene.rootNode.addChildNode(pivot); pivot.addChildNode(sculpture)
for node in originals { sculpture.addChildNode(node) }
pivot.eulerAngles = SCNVector3(-0.04,-0.24,0)
let camera = SCNNode(); camera.camera = SCNCamera()
camera.camera!.fieldOfView = 38; camera.camera!.zNear = 0.1; camera.camera!.zFar = 100
camera.camera!.wantsHDR = false
camera.camera!.screenSpaceAmbientOcclusionIntensity = 1.1
camera.camera!.screenSpaceAmbientOcclusionRadius = 0.3
let distance = 5.25/tan(19*Double.pi/180)
camera.position = SCNVector3(0,4.15,distance); scene.rootNode.addChildNode(camera)
for (type,intensity,p,shadow) in [(SCNLight.LightType.directional,CGFloat(850),SCNVector3(-5,10,8),true),(.omni,220,SCNVector3(5,5,-3),false),(.ambient,230,SCNVector3(0,0,0),false)] {
 let n = SCNNode(); n.light = SCNLight(); n.light!.type = type; n.light!.intensity = intensity; n.light!.color = NSColor.white
 n.light!.castsShadow = shadow; n.light!.shadowRadius = 5; n.light!.shadowSampleCount = 16; n.light!.shadowMapSize = CGSize(width:2048,height:2048); n.light!.shadowColor = NSColor(white:0,alpha:0.35); n.light!.orthographicScale = 12
 n.position = p; if type == .directional { n.look(at:SCNVector3(0,4,0)) }; scene.rootNode.addChildNode(n)
}
scene.background.contents = NSColor.clear
let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = scene; renderer.pointOfView = camera
let shot = renderer.snapshot(atTime:0,with:CGSize(width:1760,height:1840),antialiasingMode:.multisampling4X)
let bitmap = NSBitmapImageRep(data:shot.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("tree-native.png"))
func xyz(_ p:SCNVector3)->[CGFloat] {[p.x,p.y,p.z]}
let data:[String:Any] = ["source":"Sources/PasteHistory/Presentation/Tree/IvoryTreeScene.swift", "referenceCommit":"ivory-v2", "width":880,"height":920,"cameraZ":distance,"anchors":anchors.map {xyz(sculpture.convertPosition($0,to:scene.rootNode))},"root":xyz(sculpture.convertPosition(SCNVector3(0,0.25,0),to:scene.rootNode))]
try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-tree.json"))
print("Exported native SceneKit pixels and nine surface anchors")
