import AppKit
import SwiftUI

// MARK: - 参数

/// 许愿树（Wishing Tree）参数：每条剪贴记录是一张挂在枝头的许愿签。
/// 夜色 + 墨色枝干 + 朱红绳。树是**长出来的**——树干先升、枝条按新→旧
/// 依次伸展、枝头长到六成时绳从那里垂落展开（verlet 物理，不是动画曲线）。
///
/// 时间语义：最新的签挂低枝（眼前），越旧挂得越高——翻历史 = 爬树。
/// 「减少动态效果」时生长跳过、绳瞬间挂满，功能不受影响（降级不是关掉）。
enum Curtain {
    // MARK: 物理
    static let persp: CGFloat = 900
    static let gravity: CGFloat = 1300
    /// verlet 速度保留系数：0.96 = 摆一两个来回就稳（真机：角一疯就废）
    static let verletDamping: CGFloat = 0.96
    /// 环境微风：8 = 签尖轻颤
    static let windAmp: CGFloat = 8
    /// 每根绳的节点数（末端节点是签，重物）
    static let nodes = 6
    /// 距离约束迭代次数
    static let iterations = 3

    // 冲量（px/帧）：拨一下的量级
    static let kick: CGFloat = 3
    static let kickFast: CGFloat = 4
    static let hoverKick: CGFloat = 1.5
    static let wakeKick: CGFloat = 1.5

    /// 摆角硬限位（度）：真许愿签是重物，摆幅天然有限、绳会绷住——
    /// 冲量再大也不能翻上枝头。超过即把签拉回弧线并泄掉切向速度
    static let maxSwingDeg: CGFloat = 22
    /// 卡面转角系数：卡重、绳软，卡的转动只跟随绳角的六成
    static let cardAngleFactor: CGFloat = 0.6

    static let cameraLerp: CGFloat = 0.12
    /// 鼠标视差：近签动多、远签动少。工具面板的 3D 是可感知不可操纵的
    static let parallax: CGFloat = 0.10
    /// 深度雾下限：外缘（更远）的签最淡到 0.62（0.55 太洗白，远签失读）
    static let fogFloor: CGFloat = 0.62
    /// 纸签卡宽（未缩放）：真机截图实锤 150 宽 + 110 高的图卡在 809×500 里
    /// 一屏必然叠压——许愿签就该是签的尺度
    static let cardWidth: CGFloat = 124

    // MARK: 树布局（世界坐标：y 向下。四条**竖直列**——列内 ↓ 垂直向下、
    // 列间互不漂移；上一版列在对角线上漂移 + 远端长枝近乎水平，真机
    // 「完全不能看」。列固定 x，卡片横向留足间隙，枝短而向上）
    /// 一屏最多 16 条 = 4 列 × 4 层；更早的滚轮/方向键翻枝
    static let maxBranches = 16
    /// 树干基座（世界 y）
    static let trunkBaseY: CGFloat = 560
    /// 列的固定 x（比例）：中两列最新（顶芽在树冠正中），外两列更旧更深
    static let columns: [CGFloat] = [0.19, 0.40, 0.60, 0.81]
    /// 各列深度：外列更深更远更小（越旧越远）
    static let columnDepth: [CGFloat] = [280, 40, 40, 280]
    /// 各列的绳长（列内 4 层）：错出对角节奏
    static let columnRope: [[CGFloat]] = [[15, 50, 25, 60],
                                           [25, 60, 15, 50],
                                           [60, 15, 50, 25],
                                           [50, 25, 60, 15]]
    /// 列内层距
    static let levelBaseY: CGFloat = 78
    static let levelStep: CGFloat = 92
    /// 外列的枝在树干上着生得更低（枝更陡，不横伸）
    static let outerBranchDrop: CGFloat = 130
    static let innerBranchDrop: CGFloat = 90
    /// 场景内容底边（相机钳制用）
    static let contentBottomY: CGFloat = 505
    /// 树干横向位置
    static let spineXRatio: CGFloat = 0.47

    static func column(_ i: Int) -> Int { i / 4 }
    /// 列内第几层（往下）：↓ 沿一列垂直向下
    static func level(_ i: Int) -> Int { i % 4 }

    static func tipX(_ i: Int, width: CGFloat) -> CGFloat {
        let jitter = 5 * sin(CGFloat(i) * 5.7)
        let raw = width * columns[column(i)] + jitter
        let pad = cardWidth / 2 + 6
        return min(max(raw, pad), width - pad)
    }

    /// 挂点 y：列内自上而下等距
    static func tipY(_ i: Int) -> CGFloat { levelBaseY + CGFloat(level(i)) * levelStep }

    static func ropeLength(_ i: Int) -> CGFloat { columnRope[column(i)][level(i)] }

    static func depth(_ i: Int) -> CGFloat { columnDepth[column(i)] }

    // MARK: 生长
    /// 整棵树长出来的总时长
    static let growDuration: TimeInterval = 1.15
    /// 树干先长：growth 的前 45% 都是树干
    static let trunkPhase: CGFloat = 0.45
    /// 枝的出场：i=0 在 0.30 开始伸，最后一条在 0.78，每条伸 0.22
    static let branchStartBase: CGFloat = 0.30
    static let branchStagger: CGFloat = 0.48
    static let branchWindow: CGFloat = 0.22
    /// 枝长到六成时，绳开始从枝头垂落
    static let hangAt: CGFloat = 0.6
    /// 绳垂落（约束目标长度展开到全长）的时长
    static let unrollDuration: TimeInterval = 0.45

    // MARK: 夜色（许愿树是一个「场景」，不随系统外观切换）
    static let nightBg = Color(red: 0.106, green: 0.082, blue: 0.063)
    // 枝干要在夜色里**看得见**：真机截图实锤 #2E2318 与夜底几乎同色、树隐形。
    // 提到暖棕中调，剪影式浮出（比夜底亮约一倍亮度）
    static let inkBranch = Color(red: 0.478, green: 0.361, blue: 0.243)
    static let bead = Color(red: 0.659, green: 0.498, blue: 0.333)
    static let ropeRed = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let ropeRedSelected = Color(red: 0.910, green: 0.333, blue: 0.247)
    static let paperBg = Color(red: 0.961, green: 0.914, blue: 0.812)
    /// 悬停微亮：纸被指尖碰到的那种变化
    static let paperHover = Color(red: 0.980, green: 0.941, blue: 0.855)
    static let paperBorder = Color(red: 0.851, green: 0.722, blue: 0.467)
    static let paperText = Color(red: 0.173, green: 0.141, blue: 0.094)
    static let paperMeta = Color(red: 0.431, green: 0.329, blue: 0.200)
    static let glow = Color(red: 1.0, green: 0.745, blue: 0.431)
    static let moon = Color(red: 0.910, green: 0.835, blue: 0.659)
    /// 树皮高光：主干上一层浅芯，两笔出体积
    static let barkHighlight = Color(red: 0.541, green: 0.416, blue: 0.282)

    /// 冒烟：--view tags 强制许愿树（不写用户偏好）
    static var debugForce = false
}

// MARK: - 物理

/// 一帧的投影结果：View 只消费，不做投影计算
struct CurtainPlacement: Identifiable {
    let id: UUID
    /// 在 results 里的索引（点击选中用）
    let index: Int
    let depth: CGFloat
    let scale: CGFloat
    let fog: CGFloat
    /// 绳末端与竖直方向的夹角（度）
    let angle: CGFloat
    /// 挂签点（屏幕坐标，卡片的 top-center 对齐到这里）
    let hang: CGPoint
    /// 绳的投影折线（Canvas 画线用）
    let path: [CGPoint]
    /// 生长淡入（0 = 绳刚从枝头垂下，1 = 挂稳）
    let alpha: CGFloat
}

/// 许愿树物理与投影。只在 SwiftUI 渲染线程（main）被 View 调用，
/// 不标 @MainActor 是因为 @State 默认值在 View 的非隔离 init 里创建
final class CurtainSim {
    struct Node { var x: CGFloat; var y: CGFloat; var px: CGFloat; var py: CGFloat }

    private final class Rope {
        var anchor: CGPoint
        let fullSeg: CGFloat
        var nodes: [Node]
        let phase: CGFloat
        /// 枝头长到六成时置为当前时间：绳开始垂落
        var spawnedAt: Date?

        init(index: Int, width: CGFloat) {
            anchor = CGPoint(x: Curtain.tipX(index, width: width), y: Curtain.tipY(index))
            fullSeg = Curtain.ropeLength(index) / CGFloat(Curtain.nodes)
            // 出生姿态：所有节点收拢在枝头附近（垂落靠约束目标长度逐步展开）
            var ns: [Node] = []
            for j in 0..<Curtain.nodes {
                let y = anchor.y + CGFloat(j) * 3
                ns.append(Node(x: anchor.x, y: y, px: anchor.x, py: y))
            }
            nodes = ns
            phase = CGFloat.random(in: 0..<(2 * .pi))
        }

        /// 重新收拢回枝头（每次打开面板，树重新长一遍）
        func restack() {
            spawnedAt = nil
            for j in nodes.indices {
                nodes[j] = Node(x: anchor.x, y: anchor.y + CGFloat(j) * 3,
                                px: anchor.x, py: anchor.y + CGFloat(j) * 3)
            }
        }
    }

    private var ropes: [UUID: Rope] = [:]
    private var lastDate: Date?
    /// 相机纵向位置（世界坐标）：最新在顶、内容向下延伸，正 = 向下滚
    private var cameraY: CGFloat = 0
    private var cameraTargetY: CGFloat = 0
    /// 相机横向平移（视差）
    private var panX: CGFloat = 0
    private var hoverX: CGFloat?
    /// 生长：nil = 还没开始长（首帧不是「长成的树闪一下再重长」）
    private var growthStart: Date?
    /// 树的世界宽度：宽度变化 >0.5pt 时整树重排（见 frame）
    private var treeWidth: CGFloat = 500
    /// 一棵树一屏：树上挂 [windowStart, windowStart+16) 这一段；
    /// 翻到树的末尾 = **整棵换下一棵**（新树重新长出来 = 翻页动画）
    private(set) var windowStart = 0
    private var totalItems = 0
    private var scrollAccum: CGFloat = 0
    private var viewportH: CGFloat = 500

    // MARK: 外部输入

    func setHover(_ x: CGFloat?) { hoverX = x }

    /// 滚轮：整棵换树。相机只在面板被压矮时兜底；正常情况树一屏装下，
    /// 滚轮 = 直接翻到上一棵/下一棵树（新树重新长出来 = 翻页动画）
    func scroll(by delta: CGFloat) {
        let maxCam = max(0, Curtain.contentBottomY - viewportH)
        let step = Curtain.maxBranches
        let maxStart = max(0, (max(totalItems - 1, 0) / step) * step)
        if delta < 0 {
            if cameraTargetY < maxCam - 1 {
                cameraTargetY = min(maxCam, cameraTargetY - delta)
            } else if windowStart < maxStart {
                scrollAccum += delta
                while scrollAccum <= -24, windowStart < maxStart {
                    windowStart += step
                    scrollAccum += 24
                }
                snapCamera()
                beginGrowth()
            }
        } else if delta > 0 {
            if cameraTargetY > 1 {
                cameraTargetY = max(0, cameraTargetY - delta)
            } else if windowStart > 0 {
                scrollAccum += delta
                while scrollAccum >= 24, windowStart > 0 {
                    windowStart -= step
                    scrollAccum -= 24
                }
                snapCamera()
                beginGrowth()
            }
        }
    }

    private func clampWindow() {
        let step = Curtain.maxBranches
        let maxStart = max(0, (max(totalItems - 1, 0) / step) * step)
        windowStart = min(max(0, windowStart), maxStart)
        windowStart = (windowStart / step) * step
    }

    /// 方向键：选中的记录在哪棵树就把哪棵树挂上来（换树时重新长）。
    /// 返回选中项的局部索引
    @discardableResult
    func ensureVisible(_ global: Int) -> Int {
        let step = Curtain.maxBranches
        let cap = min(max(totalItems - windowStart, 0), step)
        guard cap > 0 else { return 0 }
        let treeStart = (global / step) * step
        if treeStart != windowStart {
            windowStart = treeStart
            snapCamera()
            beginGrowth()
        }
        return min(max(global - windowStart, 0), cap - 1)
    }

    /// 踢一下绳末端（速度冲量，px/帧）。选中 / 悬停都走这里
    func kick(id: UUID, _ velocity: CGFloat) {
        guard !Motion.reduceMotion, let rope = ropes[id], let last = rope.nodes.indices.last else { return }
        rope.nodes[last].px -= velocity
    }

    /// 相机跟到选中签（局部索引）：签落在视口 38% 高的位置，
    /// 上不越过树冠、下不露出树脚以下
    func updateCamera(index: Int, height: CGFloat) {
        let raw = Curtain.tipY(index) + Curtain.ropeLength(index) - height * 0.38
        let maxCam = max(0, Curtain.contentBottomY - height)
        cameraTargetY = min(max(0, raw), maxCam)
    }

    /// 回到树冠：**只动相机**。（这里曾藏着 windowStart = 0——ensureVisible
    /// 换树后紧跟的 snapCamera 把刚设好的窗口清回第一棵树，导致跨树边界后
    /// 每按一次方向键 treeStart ≠ windowStart 恒成立、整棵树每按必重长，
    /// 真机 bug 两轮才抓到。窗口归零从此只走 resetToFirstTree）
    func snapCamera() {
        cameraTargetY = 0
        cameraY = 0
    }

    /// 回到第一棵树（重开面板 / 换搜索词 = 一次新的「找」）
    func resetToFirstTree() {
        windowStart = 0
        snapCamera()
    }

    /// 树重新长一遍：每次打开面板都是一次「长出来」
    func beginGrowth() {
        if Motion.reduceMotion {
            growthStart = .distantPast
            for rope in ropes.values { rope.spawnedAt = .distantPast }
        } else {
            growthStart = Date()
            for rope in ropes.values { rope.restack() }
        }
    }

    /// Canvas 画树干/枝/光用的相机偏移
    var cameraOffset: CGFloat { cameraY }
    /// Canvas 画枝用的世界宽度
    var layoutWidth: CGFloat { treeWidth }
    /// Canvas 用的即时生长进度
    var currentGrowth: CGFloat { growth(at: Date()) }

    /// 生长进度（easeOutCubic，0 = 光秃秃 / 还没开始，1 = 长成）
    private func growth(at date: Date) -> CGFloat {
        guard let start = growthStart else { return 0 }
        let t = date.timeIntervalSince(start) / Curtain.growDuration
        guard t < 1 else { return 1 }
        let u = CGFloat(max(0, t))
        return 1 - pow(1 - u, 3)
    }

    /// 第 i 条枝的生长进度（0 = 还没冒头，1 = 伸完）
    func branchProgress(_ i: Int, count: Int, growth: CGFloat) -> CGFloat {
        let start = Curtain.branchStartBase
            + Curtain.branchStagger * CGFloat(i) / CGFloat(max(count, 1))
        return min(1, max(0, (growth - start) / Curtain.branchWindow))
    }

    // MARK: 每帧

    /// 对账（新记录挂新枝、消失的记录解绳）→ 物理步进 → 投影。
    /// 由 TimelineView(.animation) 每帧调用一次
    func frame(date: Date, items: [ClipItem], width: CGFloat, height: CGFloat) -> [CurtainPlacement] {
        let dt = min(0.05, lastDate.map { date.timeIntervalSince($0) } ?? 1 / 60)
        lastDate = date
        let growth = growth(at: date)
        totalItems = items.count
        viewportH = height
        clampWindow()
        let cap = min(max(items.count - windowStart, 0), Curtain.maxBranches)
        guard cap > 0 else {
            ropes.removeAll()
            return []
        }
        let window = Array(items[windowStart..<(windowStart + cap)])

        // 对账：树上只挂窗口内这 16 条；宽度变了整树重排
        // （只挪锚点不解绳——node0 被钉在新枝位，绳会荡过去，不闪不重播）
        let treeIds = Set(window.map(\.id))
        let stale = ropes.keys.filter { !treeIds.contains($0) }
        stale.forEach { ropes.removeValue(forKey: $0) }
        if ropes.isEmpty { treeWidth = width }
        let relayout = abs(width - treeWidth) > 0.5
        if relayout { treeWidth = width }
        for (li, item) in window.enumerated() {
            let want = CGPoint(x: Curtain.tipX(li, width: treeWidth), y: Curtain.tipY(li))
            if let rope = ropes[item.id] {
                if relayout || rope.anchor != want { rope.anchor = want }
            } else {
                ropes[item.id] = Rope(index: li, width: treeWidth)
            }
        }

        cameraY += (cameraTargetY - cameraY) * Curtain.cameraLerp
        let panTarget: CGFloat
        if Motion.reduceMotion {
            panTarget = 0
        } else {
            panTarget = hoverX.map { ($0 - width / 2) * Curtain.parallax } ?? 0
        }
        panX += (panTarget - panX) * 0.1

        // 枝头长到六成 → 绳开始垂落
        for (li, item) in window.enumerated() {
            if let rope = ropes[item.id], rope.spawnedAt == nil,
               branchProgress(li, count: cap, growth: growth) >= Curtain.hangAt {
                rope.spawnedAt = date
                if !Motion.reduceMotion {
                    rope.nodes[rope.nodes.count - 1].px -= .random(in: -1...1)
                }
            }
        }

        step(dt: dt, now: date.timeIntervalSinceReferenceDate)

        var tags: [CurtainPlacement] = []
        let cx = width / 2
        for (li, item) in window.enumerated() {
            guard let rope = ropes[item.id], let spawned = rope.spawnedAt else { continue }
            let z = Curtain.depth(li)
            let s = Curtain.persp / (Curtain.persp + z)
            let panX = self.panX
            let cameraY = self.cameraY
            let project: (Node) -> CGPoint = { n in
                CGPoint(x: cx + (n.x - cx) * s + panX * s,
                        y: (n.y - cameraY) * s)
            }
            let hang = project(rope.nodes[rope.nodes.count - 1])
            // 视口裁剪：卡高约 80/scale，上下留裕量
            if hang.y < -140 || hang.y > height + 180 { continue }
            let prev = project(rope.nodes[rope.nodes.count - 2])
            // 卡面转角只取绳角的六成：卡重绳软，卡的转动滞后于绳
            let angle = atan2(hang.x - prev.x, hang.y - prev.y) * 180 / .pi * Curtain.cardAngleFactor
            // 挂稳程度：垂落后的前 0.25s 淡入
            let age = date.timeIntervalSince(spawned)
            let alpha = min(1, max(0, CGFloat(age / 0.25)))
            tags.append(CurtainPlacement(
                id: item.id,
                index: windowStart + li,
                depth: z,
                scale: s,
                fog: Curtain.fogFloor + (1 - Curtain.fogFloor) * s,
                angle: angle,
                hang: hang,
                path: rope.nodes.map(project),
                alpha: alpha))
        }
        // 深的先画（在底下），浅的后画（盖上来）；选中项的 zIndex 在 View 里给
        tags.sort { $0.depth > $1.depth }
        return tags
    }

    /// verlet 积分 + 距离约束。约束的目标长度按垂落进度展开（0 → 全长）：
    /// 绳从枝头「长」出来，重力把它拉直——这是生长动画的物理实现。
    /// 两条稳定器（真机截图实锤没有它们签会疯）：
    /// 1. 垂落期间绳锁直在锚点正下方（风关、x 钉死）——散开的绳从收拢
    ///    状态展开会甩成 S 形，永远回不到「挂稳」的初始印象
    /// 2. 摆角硬限位 ±maxSwingDeg：超限把签拉回弧线并泄掉切向速度
    private func step(dt: TimeInterval, now: TimeInterval) {
        let dt2 = CGFloat(dt * dt)
        for rope in ropes.values {
            guard let spawned = rope.spawnedAt else { continue }
            let age = now - spawned.timeIntervalSinceReferenceDate
            let u = CGFloat(min(1, max(0, age / Curtain.unrollDuration)))
            let segNow = rope.fullSeg * (1 - pow(1 - u, 3))
            guard segNow > 0.5 else { continue }
            let unrolling = u < 0.7

            let n = rope.nodes
            var m = n
            for j in m.indices.dropFirst() {
                let vx = (m[j].x - m[j].px) * Curtain.verletDamping
                let vy = (m[j].y - m[j].py) * Curtain.verletDamping
                m[j].px = m[j].x
                m[j].py = m[j].y
                let wind = (Motion.reduceMotion || unrolling) ? 0
                    : Curtain.windAmp * (0.7 * CGFloat(sin(now * 0.55 + Double(rope.phase) + Double(j) / Double(Curtain.nodes)))
                        + 0.3 * CGFloat(sin(now * 1.35 + Double(rope.phase) * 1.7 + Double(j) / Double(Curtain.nodes))))
                m[j].x += vx + wind * dt2
                m[j].y += vy + Curtain.gravity * dt2
            }
            for _ in 0..<Curtain.iterations {
                for j in m.indices.dropFirst() {
                    let dx = m[j].x - m[j - 1].x
                    let dy = m[j].y - m[j - 1].y
                    let dist = (dx * dx + dy * dy).squareRoot()
                    guard dist > 0.0001 else { continue }
                    let diff = (dist - segNow) / dist
                    let wa: CGFloat
                    let wb: CGFloat
                    if j == m.count - 1 { wa = 0.85; wb = 0.15 }   // 末端是签：重物几乎不动，绳让位
                    else if j == 1 { wa = 0; wb = 1 }
                    else { wa = 0.5; wb = 0.5 }
                    m[j - 1].x += dx * diff * wa
                    m[j - 1].y += dy * diff * wa
                    m[j].x -= dx * diff * wb
                    m[j].y -= dy * diff * wb
                }
                let a0 = rope.anchor
                m[0].x = a0.x
                m[0].y = a0.y
                m[0].px = a0.x
                m[0].py = a0.y
            }
            if unrolling {
                // 垂落期间锁直：绳只会从枝头正下方展开
                for j in m.indices.dropFirst() { m[j].x = rope.anchor.x }
            } else {
                // 摆角限位：超过 ±maxSwingDeg 拉回弧线 + 泄掉一半切向速度
                let last = m.count - 1
                let dx = m[last].x - rope.anchor.x
                let dy = m[last].y - rope.anchor.y
                let maxAng = Curtain.maxSwingDeg * .pi / 180
                let ang = atan2(dx, dy)
                if abs(ang) > maxAng, dy > 0 {
                    let capped = max(-maxAng, min(maxAng, ang))
                    let dist = (dx * dx + dy * dy).squareRoot()
                    m[last].x = rope.anchor.x + sin(capped) * dist
                    m[last].y = rope.anchor.y + cos(capped) * dist
                    m[last].px = m[last].x - (m[last].x - m[last].px) * 0.5
                    m[last].py = m[last].y - (m[last].y - m[last].py) * 0.5
                }
            }
            rope.nodes = m
        }
    }
}

// MARK: - 视图

/// 剪贴历史的「许愿树」视图：列表的兄弟视图（⌘L 互切），共享同一个
/// HistoryViewModel——键盘导航、⌘N、空格预览、置顶、删除全部原样可用。
struct TagCurtainView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject private var model: HistoryViewModel
    let onPaste: (ClipItem) -> Void
    @State private var sim = CurtainSim()

    init(store: ClipStore,
         model: HistoryViewModel,
         onPaste: @escaping (ClipItem) -> Void) {
        self.store = store
        self.model = model
        self.onPaste = onPaste
    }

    private var items: [ClipItem] { model.results }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let snapshot = sim.frame(date: timeline.date,
                                         items: items,
                                         width: geo.size.width,
                                         height: geo.size.height)
                let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let selectedId = model.current?.id
                ZStack(alignment: .topLeading) {
                    treeCanvas(snapshot: snapshot,
                               selectedId: selectedId,
                               width: geo.size.width,
                               height: geo.size.height)
                    ForEach(snapshot) { p in
                        if let item = byId[p.id] {
                            TagCard(item: item, selected: p.id == selectedId)
                                .scaleEffect(p.scale, anchor: .top)
                                .rotationEffect(.degrees(p.angle), anchor: .top)
                                .offset(x: p.hang.x - Curtain.cardWidth / 2, y: p.hang.y)
                                .zIndex(p.id == selectedId ? 2000 : 1000 - p.depth)
                                .opacity(p.alpha)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { onPaste(item) }
                                .simultaneousGesture(TapGesture().onEnded { model.select(p.index) })
                                .onHover { entering in
                                    if entering {
                                        sim.kick(id: p.id, (Bool.random() ? -1 : 1) * Curtain.hoverKick)
                                    }
                                }
                        }
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): sim.setHover(location.x)
                case .ended: sim.setHover(nil)
                }
            }
            .background(ScrollCatcher { delta in
                // 换树时把选中同步到新树的第一条——不然第一次按方向键
                // 会带着选中跳回旧树、整棵树再长一遍（真机 bug 实锤）
                let before = sim.windowStart
                sim.scroll(by: delta)
                if sim.windowStart != before {
                    model.select(sim.windowStart)
                }
            })
            .overlay(alignment: .bottomTrailing) {
                Text(L10n.curtainListHint)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Curtain.moon.opacity(0.8))
                    .padding(.horizontal, Rhythm.m)
                    .padding(.vertical, Rhythm.s)
                    .background(Capsule().fill(Curtain.nightBg.opacity(0.8)))
                    .padding(Rhythm.s)
            }
            .overlay(alignment: .center) {
                if items.isEmpty { emptyState }
            }
            .overlay(alignment: .bottom) {
                // 树是窗口式挂枝：还有更早的记录时给出去处
                if sim.windowStart + Curtain.maxBranches < items.count {
                    Text(L10n.curtainOlderHint)
                        .font(.system(size: Scale.meta))
                        .foregroundStyle(Curtain.moon.opacity(0.8))
                        .padding(.horizontal, Rhythm.m)
                        .padding(.vertical, Rhythm.s)
                        .background(Capsule().fill(Curtain.nightBg.opacity(0.8)))
                        .padding(Rhythm.s)
                }
            }
            .onAppear {
                model.resetSelection()
                sim.beginGrowth()
            }
            .onChange(of: model.safeSelection) { old, new in
                handleSelectionChange(old: old, new: new, height: geo.size.height)
            }
            .onChange(of: model.presentationTick) { _, _ in
                sim.resetToFirstTree()
                sim.beginGrowth()
            }
            .onChange(of: store.query) { _, _ in
                model.resetSelection()
                sim.resetToFirstTree()
            }
        }
    }

    // MARK: Canvas（夜色 / 树 / 绳）

    private func treeCanvas(snapshot: [CurtainPlacement],
                            selectedId: UUID?,
                            width: CGFloat,
                            height: CGFloat) -> some View {
        Canvas { ctx, size in
            drawSky(ctx: ctx, size: size, cameraY: sim.cameraOffset, width: width)
            if !items.isEmpty {
                drawTree(ctx: &ctx, size: size, cameraY: sim.cameraOffset, width: width)
            }
            drawRopes(ctx: ctx, snapshot: snapshot, selectedId: selectedId)
        }
    }

    /// 夜色 + 星空 + 树冠暖光 + 月（世界坐标，随相机滚动）
    private func drawSky(ctx: GraphicsContext, size: CGSize, cameraY: CGFloat, width: CGFloat) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Curtain.nightBg))
        // 星：确定性散布（137 步长伪随机），三两颗大些，微微明灭——
        // 夜空有了纵深，整幅画立刻不像「黑底」而是「夜」
        let t = Date().timeIntervalSinceReferenceDate
        let w = max(Int(width), 1)
        for i in 0..<26 {
            let sx = CGFloat((i * 137 + 53) % w)
            let sy = CGFloat((i * 89 + 17) % 150) - cameraY * 0.6
            let starSize: CGFloat = i % 7 == 0 ? 2.0 : 1.2
            let base = 0.10 + 0.16 * CGFloat((i * 31) % 10) / 10
            let twinkle: CGFloat = Motion.reduceMotion
                ? 1.0
                : 0.75 + 0.25 * CGFloat(sin(t * 0.8 + Double(i) * 1.7))
            let rect = CGRect(x: sx, y: sy, width: starSize, height: starSize)
            ctx.fill(Path(ellipseIn: rect), with: .color(Curtain.moon.opacity(base * twinkle)))
        }
        let glowY = 190 - cameraY
        let glowRect = CGRect(x: width * 0.5 - 210, y: glowY - 210, width: 420, height: 420)
        ctx.fill(Path(ellipseIn: glowRect), with: .color(Curtain.glow.opacity(0.06)))
        let moonY = 30 - cameraY
        let moonInner = CGRect(x: width * 0.9 - 15, y: moonY - 15, width: 30, height: 30)
        ctx.fill(Path(ellipseIn: moonInner), with: .color(Curtain.moon.opacity(0.14)))
        let moonOuter = CGRect(x: width * 0.9 - 25, y: moonY - 25, width: 50, height: 50)
        ctx.fill(Path(ellipseIn: moonOuter), with: .color(Curtain.moon.opacity(0.07)))
    }

    /// 树干（clip 从底部向上长）+ 斜枝（从树干伸向每个挂点，按进度伸展）
    private func drawTree(ctx: inout GraphicsContext, size: CGSize, cameraY: CGFloat, width: CGFloat) {
        let growth = sim.currentGrowth
        let count = min(max(items.count - sim.windowStart, 0), Curtain.maxBranches)
        let layoutWidth = sim.layoutWidth
        let trunkX = Curtain.spineXRatio * layoutWidth
        let crownY = Curtain.levelBaseY - 52

        let trunkGrowth = min(1, growth / Curtain.trunkPhase)
        if trunkGrowth > 0.01 {
            let clipRect = CGRect(x: 0, y: size.height * (1 - trunkGrowth),
                                  width: size.width, height: size.height * trunkGrowth)
            ctx.clip(to: Path(clipRect))
            let base = CGPoint(x: trunkX, y: Curtain.trunkBaseY - cameraY)
            let top = CGPoint(x: trunkX, y: crownY - cameraY)
            let mid = CGPoint(x: trunkX + 10, y: (Curtain.trunkBaseY + crownY) / 2 - cameraY)
            var trunk = Path()
            trunk.move(to: base)
            trunk.addQuadCurve(to: top, control: mid)
            ctx.stroke(trunk, with: .color(Curtain.inkBranch),
                       style: StrokeStyle(lineWidth: 16, lineCap: .round))
            // 浅芯一笔 = 受光的树皮，两笔出体积
            ctx.stroke(trunk, with: .color(Curtain.barkHighlight),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
            // 侧根两条：必须画在视口内——树要看得见「扎根」，不是悬空
            // （之前画在 y530-590，视口只有 438 高，等于没画）
            let rootY = min(415 - cameraY, size.height - 12)
            var rootL = Path()
            rootL.move(to: CGPoint(x: trunkX, y: rootY + 34))
            rootL.addQuadCurve(to: CGPoint(x: trunkX - 44, y: rootY),
                               control: CGPoint(x: trunkX - 26, y: rootY + 22))
            ctx.stroke(rootL, with: .color(Curtain.inkBranch),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
            var rootR = Path()
            rootR.move(to: CGPoint(x: trunkX, y: rootY + 34))
            rootR.addQuadCurve(to: CGPoint(x: trunkX + 38, y: rootY - 4),
                               control: CGPoint(x: trunkX + 22, y: rootY + 20))
            ctx.stroke(rootR, with: .color(Curtain.inkBranch),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }

        // 斜枝：每条枝从树干出发伸向挂点（着生点低于挂点，向上向外伸）。
        // 外列的枝着生得更低 → 更陡，不横伸；按生长进度画部分曲线
        for li in 0..<count {
            let b = sim.branchProgress(li, count: max(count, 1), growth: growth)
            guard b > 0.01 else { continue }
            let tipY = Curtain.tipY(li)
            let drop = Curtain.columnDepth[Curtain.column(li)] > 100
                ? Curtain.outerBranchDrop
                : Curtain.innerBranchDrop
            let sy = min(tipY + drop, Curtain.trunkBaseY - 40)
            let start = CGPoint(x: trunkX, y: sy - cameraY)
            let tip = CGPoint(x: Curtain.tipX(li, width: layoutWidth), y: tipY - cameraY)
            let control = CGPoint(x: (start.x + tip.x) / 2, y: (start.y + tip.y) / 2 - 24)
            let u = 1 - pow(1 - b, 2)
            let mu = 1 - u
            let end = CGPoint(x: mu * mu * start.x + 2 * mu * u * control.x + u * u * tip.x,
                              y: mu * mu * start.y + 2 * mu * u * control.y + u * u * tip.y)
            var branch = Path()
            branch.move(to: start)
            branch.addQuadCurve(to: end, control: control)
            ctx.stroke(branch, with: .color(Curtain.inkBranch.opacity(min(1, b * 2))),
                       style: StrokeStyle(lineWidth: max(2.2, 5.0 - (sy - tipY) / 60),
                                          lineCap: .round))
            if b > 0.9 {
                let beadRect = CGRect(x: tip.x - 2.4, y: tip.y - 2.4, width: 4.8, height: 4.8)
                ctx.fill(Path(ellipseIn: beadRect), with: .color(Curtain.bead))
            }
        }
    }

    /// 朱红绳
    private func drawRopes(ctx: GraphicsContext, snapshot: [CurtainPlacement], selectedId: UUID?) {
        for tag in snapshot {
            guard tag.path.count > 1 else { continue }
            var rope = Path()
            rope.move(to: tag.path[0])
            for point in tag.path.dropFirst() { rope.addLine(to: point) }
            let selected = tag.id == selectedId
            ctx.stroke(rope,
                       with: .color(selected ? Curtain.ropeRedSelected : Curtain.ropeRed),
                       lineWidth: selected ? 3 : max(1.6, 2.4 * tag.scale))
        }
    }

    // MARK: 交互

    private func handleSelectionChange(old: Int, new: Int, height: CGFloat) {
        guard !items.isEmpty else { return }
        let clamped = min(max(new, 0), items.count - 1)
        guard clamped >= 0, clamped < items.count else { return }
        // 方向键选到窗口外：先换枝（选中项进窗），再踢绳、跟相机
        let local = sim.ensureVisible(clamped)
        let fast = Date().timeIntervalSince(model.lastMoveAt) < Motion.repeatThreshold
        let dir: CGFloat = new >= old ? 1 : -1
        // 旧签被反向带一下：视线离开的地方也要有余波
        if old != new, old >= 0, old < items.count, items[old].id != items[clamped].id {
            sim.kick(id: items[old].id, -dir * Curtain.wakeKick)
        }
        sim.kick(id: items[clamped].id, dir * (fast ? Curtain.kickFast : Curtain.kick))
        sim.updateCamera(index: local, height: height)
        if clamped >= items.count - 8 { store.loadMore() }
    }

    private var emptyState: some View {
        VStack(spacing: Rhythm.l) {
            Text(store.totalCount == 0 ? L10n.noHistory : L10n.noMatch)
                .font(.system(size: Scale.field, weight: .medium))
                .foregroundStyle(Curtain.moon)
            Text(store.totalCount == 0 ? L10n.copySomething : L10n.tryAnother)
                .font(.system(size: Scale.body))
                .foregroundStyle(Curtain.moon.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Rhythm.xxl)
    }
}

// MARK: - 滚轮

/// 捕获滚轮的透明垫层：SwiftUI 在 macOS 14 没有滚轮修饰符，
/// 靠一个不响应点击、只转发 scrollWheel 的 NSView 铺在树后面
private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelView {
        let view = WheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: WheelView, context: Context) {
        view.onScroll = onScroll
    }

    final class WheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY)
            // 不调 super：滚动全部归树，不透给底层窗口
        }
    }
}

// MARK: - 许愿签

/// 挂在枝头的许愿签：暖纸底 + 深棕字。轻量是硬要求——
/// TimelineView 每帧重建 ZStack，卡片的 body 必须便宜
private struct TagCard: View {
    let item: ClipItem
    let selected: Bool
    @State private var hovered = false

    private var symbol: String {
        switch item.kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Rhythm.s) {
            if let thumb = item.thumbnail {
                // 图片签 = 拍立得：缩略图本身就是摘要，不再叠文字行
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Curtain.cardWidth - Rhythm.m * 2, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if item.thumbnail == nil {
                Text(item.summary)
                    .font(.system(size: Scale.body))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: Rhythm.s) {
                Image(systemName: symbol)
                    .font(.system(size: Icon.mark))
                    .foregroundStyle(Curtain.paperMeta)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: Icon.mark))
                        .foregroundStyle(Curtain.paperMeta)
                }
                Text(RelativeTime.string(from: item.createdAt))
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Curtain.paperMeta)
                Spacer(minLength: 0)
            }
        }
        .padding(Rhythm.m)
        .frame(width: Curtain.cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Curtain.paperBg)
        )
        // 无边框：纸签靠暖纸色和夜色拉开，不靠描边（真机反馈「边框就别要了」）。
        // 选中态是唯一保留的描边——红线 + 红描边一起构成最强信号
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Curtain.ropeRedSelected, lineWidth: 1.5)
                .opacity(selected ? 1 : 0)
        )
        // 投影把签从夜空里托起来；选中 = 灯笼光（暖晕，不是白光）
        .shadow(color: selected ? Curtain.glow.opacity(0.45) : Color.black.opacity(0.30),
                radius: selected ? 9 : 5,
                y: 2)
    }
}
