"""Export the native BoatMesh triangles. Run with the path to the TideDesk source directory."""
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve() / "Sources"
output = Path(__file__).resolve().parents[1] / "public/sea/assets/boats.bin"
mesh = (source / "BoatModels.swift").read_text().split("final class BoatModels {")[0]
# Indexed triangle streams store each distinct vertex once per vessel. Omit Swift SIMD padding.
export = """
var result = Data()
func append<T>(_ value: T) {
    var value = value
    withUnsafeBytes(of:&value) { result.append(contentsOf:$0) }
}
for kind in [Vessel.sloop, .freighter, .cruiser, .launch] {
  for variant in 0..<4 {
    let mesh = BoatMesh(kind:kind,variant:variant)
    var unique = [[Float]](), ids = [[Float]:UInt16](), indices = [UInt16]()
    for v in mesh.vertices {
        let key = [v.position.x,v.position.y,v.position.z,v.normal.x,v.normal.y,v.normal.z,
                   v.pigment.x,v.pigment.y,v.pigment.z,v.windowGlow]
        if ids[key] == nil { ids[key] = UInt16(unique.count); unique.append(key) }
        indices.append(ids[key]!)
    }
    append(UInt32(unique.count)); append(UInt32(indices.count))
    for v in unique { for f in v { append(f) } }
    for i in indices { append(i) }
    while result.count % 4 != 0 {append(UInt8(0))}
  }
}
try result.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
"""
with tempfile.TemporaryDirectory() as folder:
    main = Path(folder) / "main.swift"
    main.write_text(mesh + export)
    binary = Path(folder) / "export"
    subprocess.run(["swiftc", str(source / "Fleet.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(output)], check=True)
