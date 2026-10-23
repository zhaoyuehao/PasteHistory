import AppKit
import SceneKit
import SwiftUI

// MARK: - 黄铜雕塑树（生成模型 → SceneKit 实时渲染）

/// 许愿树的雕塑本体：AI 生成的黄铜枝条装置（Hunyuan text-to-3D → OBJ，
/// 贴图剥离、材质替换为程序化黄铜 PBR → brass_tree.scn，11.9MB）。
/// 挂点标定由 models/calibrate.swift 完成：以 W=809 网格搜索得 K=800、
/// Y0=820——16 个挂点到雕塑表面**平均 7.5pt、最差 26pt**，绳全都落在真枝条上。
///
/// 坐标系对齐：挂点布局在面板坐标（y 向下），SceneKit y 向上、相机在
/// z=persp(900) 看向 -z。映射：px = W/2 + v.x·K，py = Y0 - v.y·K；
/// 组节点 world y = H/2 - Y0 + v.y·K，相机 fov 贴面板高度使 z=0 平面
/// 1 world unit = 1pt——绳/卡的透视缩放（persp 常数）与雕塑共用同一相机。
enum CurtainBrass {
    /// 标定比：K = width × 0.989（挂点 x 与列宽同比缩放）
    static let kRatio: CGFloat = 0.989
    /// 标定基：Y0 = 216 + 0.75·K（模型 y=0.75 对准挂点带中心 y=216）
    static let y0Base: CGFloat = 216
    static let y0K: CGFloat = 0.75
    static let modelTop: CGFloat = 1.14

    static let scene: SCNScene? = {
        guard let url = Bundle.module.url(forResource: "brass_tree", withExtension: "scn"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }

        scene.background.contents = nil
        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 0.9

        // 模型收进「brass」组：生长动画/视差都打在这个组上
        let group = SCNNode()
        group.name = "brass"
        for child in Array(scene.rootNode.childNodes) where child.camera == nil {
            group.addChildNode(child)
        }
        scene.rootNode.addChildNode(group)

        // 相机：与绳/卡共享 persp=900，fov 每帧贴面板高度（z=0 平面 1:1）
        let cam = SCNNode()
        cam.name = "camera"
        cam.camera = SCNCamera()
        cam.camera?.zNear = 10
        cam.camera?.zFar = 4000
        cam.position = SCNVector3(0, 0, Float(Curtain.persp))
        scene.rootNode.addChildNode(cam)

        // 冠心暖光：Canvas 里的树冠光晕物理化——黄铜被它照出暖芯
        let glow = SCNNode()
        glow.light = SCNLight()
        glow.light?.type = .omni
        glow.light?.color = NSColor(red: 1.0, green: 0.745, blue: 0.431, alpha: 1)
        glow.light?.intensity = 700
        glow.position = SCNVector3(0, 120, 480)
        scene.rootNode.addChildNode(glow)

        // 月光：右上侧逆光（和夜空里的月同侧）
        let moon = SCNNode()
        moon.light = SCNLight()
        moon.light?.type = .directional
        moon.light?.color = NSColor(red: 0.910, green: 0.835, blue: 0.659, alpha: 1)
        moon.light?.intensity = 380
        moon.eulerAngles = SCNVector3(-0.9, 0.35, 0)
        scene.rootNode.addChildNode(moon)

        // 夜色反照底光
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.color = NSColor(red: 0.24, green: 0.19, blue: 0.14, alpha: 1)
        amb.light?.intensity = 90
        scene.rootNode.addChildNode(amb)

        return scene
    }()

    /// IBL 环境图：程序化画（夜底 + 冠心暖斑 + 右上月斑）——
    /// 金属材质没有环境光就是黑铁，这个给了黄铜反射的灵魂
    private static func environmentImage() -> NSImage {
        let size = CGSize(width: 512, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.09, green: 0.07, blue: 0.055, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        func blob(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor, _ alpha: CGFloat) {
            guard let cg = NSGraphicsContext.current?.cgContext else { return }
            let center = CGPoint(x: size.width * cx, y: size.height * cy)
            let radius = min(size.width, size.height) * r
            let colors = [color.withAlphaComponent(alpha).cgColor,
                          color.withAlphaComponent(0).cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) else { return }
            cg.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: radius, options: [])
        }
        blob(0.5, 0.72, 0.30, NSColor(red: 1.0, green: 0.745, blue: 0.431, alpha: 1), 0.50)
        blob(0.88, 0.88, 0.16, NSColor(red: 0.910, green: 0.835, blue: 0.659, alpha: 1), 0.30)
        image.unlockFocus()
        return image
    }
}

/// 雕塑舞台：透明背景的 SCNView，垫在夜空 Canvas 之上、绳与卡之下。
/// TimelineView 每帧把 growth/panX/cameraY/尺寸推进来，SCNView 按需重渲
struct CurtainStage: View {
    let growth: CGFloat
    let panX: CGFloat
    let cameraY: CGFloat
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        CurtainStageRepresentable(growth: growth, panX: panX, cameraY: cameraY,
                                   width: width, height: height)
    }
}

/// 树是可感知不可操纵的：hitTest 恒 nil 让 3D 层对一切鼠标事件透明——
/// 滚轮照常落到底下的 ScrollCatcher，点击/悬停照常归 SwiftUI
private final class PassthroughSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct CurtainStageRepresentable: NSViewRepresentable {
    let growth: CGFloat
    let panX: CGFloat
    let cameraY: CGFloat
    let width: CGFloat
    let height: CGFloat

    /// 变化缓存：TimelineView 每帧都调 updateNSView，但雕塑只在
    /// 生长/视差/相机/尺寸变化时才需要动。值没变就一个属性都不碰——
    /// SceneKit 有写就整场重渲（PBR+IBL+MSAA），连按方向键时
    /// 无意义重渲会把合成器预算挤爆（真机卡顿实锤两轮）。
    final class Coordinator {
        var growth: CGFloat = -1
        var panX: CGFloat = .nan
        var cameraY: CGFloat = .nan
        var width: CGFloat = -1
        var height: CGFloat = -1
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PassthroughSCNView {
        let view = PassthroughSCNView()
        view.scene = CurtainBrass.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.setAccessibilityHidden(true)
        return view
    }

    func updateNSView(_ view: PassthroughSCNView, context: Context) {
        let last = context.coordinator
        let growthMoved = abs(growth - last.growth) > 0.002
        let panMoved = abs(panX - last.panX) > 0.3
        let cameraMoved = abs(cameraY - last.cameraY) > 0.3
        let resized = width != last.width || height != last.height
        guard growthMoved || panMoved || cameraMoved || resized else { return }
        last.growth = growth
        last.panX = panX
        last.cameraY = cameraY
        last.width = width
        last.height = height

        guard let scene = view.scene,
              let group = scene.rootNode.childNode(withName: "brass", recursively: false),
              let cam = scene.rootNode.childNode(withName: "camera", recursively: false) else { return }

        // 相机：fov 贴面板高度，让 z=0 平面 1 world unit = 1pt；
        // 横向微移 = 视差；纵向跟 Canvas 的相机走（爬树时抬头），
        // 绳/珠/天空和雕塑永远在同一坐标里
        if resized {
            cam.camera?.fieldOfView = 2 * atan(height / 2 / Curtain.persp) * 180 / .pi
        }
        cam.position = SCNVector3(Float(-panX), Float(-cameraY), Float(Curtain.persp))

        let k = width * CurtainBrass.kRatio
        let y0 = CurtainBrass.y0Base + CurtainBrass.y0K * k
        // 入场：雕塑自下升起 + 微 yaw 转入 + 淡入（easeOutCubic 已在 growth 里）
        let eased = Motion.reduceMotion ? 1 : growth
        let rise = (1 - eased) * 70
        let yaw = (1 - eased) * -0.10
        group.scale = SCNVector3(Float(k), Float(k), Float(k))
        group.position = SCNVector3(0, Float(height / 2 - y0 - rise), 0)
        group.eulerAngles = SCNVector3(0, Float(yaw), 0)
        group.opacity = min(1, growth * 2.5)
    }
}
