import Foundation
import SceneKit

// 顶点云：从 .scn 里读 .vertex 源
func vertices(of scene: SCNScene) -> [SIMD2<Float>] {
    var out: [SIMD2<Float>] = []
    scene.rootNode.enumerateHierarchy { node, _ in
        guard let geo = node.geometry,
              let src = geo.sources(for: .vertex).first,
              src.bytesPerComponent == 4 else { return }
        let data = src.data
        let stride = src.dataStride
        let offset = src.dataOffset
        let n = src.vectorCount
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<n {
                let base = i * stride + offset
                let f = raw.load(fromByteOffset: base, as: Float.self)
                let f2 = raw.load(fromByteOffset: base + src.bytesPerComponent, as: Float.self)
                out.append(SIMD2(f, f2))
            }
        }
    }
    return out
}

guard let scene = try? SCNScene(url: URL(fileURLWithPath: "brass_tree.scn"), options: nil) else {
    print("scn load failed"); exit(1)
}
var all = vertices(of: scene)
print("vertices=\(all.count)")
let yRange = all.map(\.y)
print(String(format: "y span %.3f...%.3f", yRange.min() ?? 0, yRange.max() ?? 1))
let xRange = all.map(\.x)
print(String(format: "x span %.3f...%.3f", xRange.min() ?? 0, xRange.max() ?? 1))

// 降采样（均匀 stride）
func sample(_ v: [SIMD2<Float>], every: Int) -> [SIMD2<Float>] {
    v.enumerated().compactMap { $0.offset % every == 0 ? $0.element : nil }
}

// 挂点（面板坐标，w=809 基准；与 Curtain 完全一致）
let W: Float = 809
let cols: [Float] = [0.19, 0.40, 0.60, 0.81]
let tipX: (Int) -> Float = { i in
    let jitter = 3 * sin(Float(i) * 5.7)
    let raw = W * cols[i / 4] + jitter
    let pad: Float = 72
    return min(max(raw, pad), W - pad)
}
let tipY: (Int) -> Float = { i in 78 + Float(i % 4) * 92 }
var anchors: [SIMD2<Float>] = []
for i in 0..<16 { anchors.append(SIMD2(tipX(i), tipY(i))) }

// 模型变换：px = W/2 + v.x*K ；py = Y0 - v.y*K
// 目标：16 个挂点到最近顶点（换回模型空间后距离）的平方和最小
func cost(_ K: Float, _ Y0: Float, _ cloud: [SIMD2<Float>]) -> (Float, Float) {
    var worst: Float = 0
    var sum: Float = 0
    for a in anchors {
        // 挂点 → 模型空间
        let mx = (a.x - W / 2) / K
        let my = (Y0 - a.y) / K
        var best: Float = .greatestFiniteMagnitude
        for v in cloud {
            let dx = v.x - mx, dy = v.y - my
            let d = dx * dx + dy * dy
            if d < best { best = d }
        }
        let dist = sqrt(best) * K
        worst = max(worst, dist)
        sum += dist
    }
    return (sum, worst)
}

var coarse = sample(all, every: 40)
var bestK: Float = 0, bestY0: Float = 0, bestSum: Float = .greatestFiniteMagnitude

// 粗搜：K 400...1400，Y0 400...1400
var K: Float = 400
while K <= 1400 {
    var Y0: Float = 400
    while Y0 <= 1400 {
        let (s, _) = cost(K, Y0, coarse)
        if s < bestSum { bestSum = s; bestK = K; bestY0 = Y0 }
        Y0 += 40
    }
    K += 40
}

// 细搜两轮（半径 = 粗步长，逐次减半）
var fine = sample(all, every: 10)
var radiusK: Float = 40, radiusY: Float = 40
for _ in 0..<2 {
    radiusK /= 2; radiusY /= 2
    var k = bestK - radiusK * 2
    while k <= bestK + radiusK * 2 {
        var y = bestY0 - radiusY * 2
        while y <= bestY0 + radiusY * 2 {
            let (s, _) = cost(k, y, fine)
            if s < bestSum { bestSum = s; bestK = k; bestY0 = y }
            y += max(2, radiusY)
        }
        k += max(2, radiusK)
    }
}

// 最终评估（更密的点云）
let dense = sample(all, every: 4)
let (sum, worst) = cost(bestK, bestY0, dense)
print(String(format: "BEST K=%.1f Y0=%.1f mean=%.1f worst=%.1f (world pt)", bestK, bestY0, sum / 16, worst))
print(String(format: "model panel width=%.0f height=%.0f", 0.85 * bestK, 1.14 * bestK))
print(String(format: "panel view of model: py(0)=%.0f py(1.14)=%.0f (frame 0..500)", bestY0, bestY0 - 1.14 * bestK))
for (i, a) in anchors.enumerated() {
    let mx = (a.x - W / 2) / bestK, my = (bestY0 - a.y) / bestK
    var bd: Float = .greatestFiniteMagnitude
    var bv = SIMD2<Float>.zero
    for v in dense {
        let dx = v.x - mx, dy = v.y - my
        let d = dx * dx + dy * dy
        if d < bd { bd = d; bv = v }
    }
    print(String(format: "anchor %d (%.0f,%.0f) -> model(%.2f,%.2f) dist=%.1f", i, a.x, a.y, bv.x, bv.y, sqrt(bd) * bestK))
}
