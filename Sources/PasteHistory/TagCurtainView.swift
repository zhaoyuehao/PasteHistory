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
    /// verlet 速度保留系数：真机反馈「抖动太厉害，不够物理」——
    /// 0.985 振荡停不下来，压到 0.975 让摆动两三个来回就归位
    static let verletDamping: CGFloat = 0.975
    /// 环境微风：12 是「叶动」而不是「风灾」
    static let windAmp: CGFloat = 12
    /// 每根绳的节点数（末端节点是签，重物）
    static let nodes = 6
    /// 距离约束迭代次数
    static let iterations = 3

    // 冲量（px/帧）：真机反馈全面调柔——踢是「拨一下」不是「抽一鞭」
    static let kick: CGFloat = 5
    static let kickFast: CGFloat = 8
    static let hoverKick: CGFloat = 2
    static let wakeKick: CGFloat = 2.5

    static let cameraLerp: CGFloat = 0.12
    /// 鼠标视差：近签动多、远签动少。工具面板的 3D 是可感知不可操纵的
    static let parallax: CGFloat = 0.10
    /// 深度雾下限：外缘（更远）的签最淡到 0.55
    static let fogFloor: CGFloat = 0.55
    /// 纸签卡宽（未缩放）
    static let cardWidth: CGFloat = 150

    // MARK: 树布局（世界坐标：y 向下；**横向枝线**结构——真机反馈
    // 「是垂直的，不是水平的」：参考图的枝线是横伸的，签成排挂在线上）
    /// 一屏最多 16 条 = 4 层枝线 × 4 个枝位；更早的滚轮/方向键翻枝
    static let maxBranches = 16
    /// 树干基座（世界 y）
    static let trunkBaseY: CGFloat = 640
    /// 第 0 层（最新）枝线高度：最新在最顶上
    static let levelBaseY: CGFloat = 92
    /// 层距：卡高 ~85 + 呼吸
    static let levelStep: CGFloat = 98
    /// 树干居中：枝线向两侧伸
    static let spineXRatio: CGFloat = 0.5
    /// 四个「枝位」：一条枝线上挂 4 张签，相邻索引换位、同位隔 4 条重现
    static let lanes: [CGFloat] = [0.15, 0.37, 0.63, 0.85]
    /// 各枝位绳长：同层内错开高度，读出对角节奏
    static let laneRope: [CGFloat] = [70, 20, 45, 95]
    /// 外侧枝位更深（远），内侧更近
    static let depthSpread: CGFloat = 320
    /// 场景内容底边（相机钳制用）
    static let contentBottomY: CGFloat = 590

    static func lane(_ i: Int) -> Int { i % lanes.count }
    static func level(_ i: Int) -> Int { i / lanes.count }

    static func tipX(_ i: Int, width: CGFloat) -> CGFloat {
        let jitter = 12 * sin(CGFloat(i) * 5.7)
        let pad = cardWidth / 2 + 6
        return min(max(width * lanes[lane(i)] + jitter, pad), width - pad)
    }

    /// 挂点 y：最新在第 0 层（最顶），满 4 条下一层
    static func tipY(_ i: Int) -> CGFloat { levelBaseY + CGFloat(level(i)) * levelStep }

    static func ropeLength(_ i: Int) -> CGFloat { laneRope[lane(i)] }

    static func depth(_ i: Int) -> CGFloat {
        60 + abs(lanes[lane(i)] - 0.5) * 2 * depthSpread
    }

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
    static let nightBg = Color(red: 0.098, green: 0.075, blue: 0.035)
    static let inkBranch = Color(red: 0.180, green: 0.137, blue: 0.094)
    static let bead = Color(red: 0.290, green: 0.220, blue: 0.165)
    static let ropeRed = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let ropeRedSelected = Color(red: 0.910, green: 0.333, blue: 0.247)
    static let paperBg = Color(red: 0.961, green: 0.914, blue: 0.812)
    static let paperBorder = Color(red: 0.851, green: 0.722, blue: 0.467)
    static let paperText = Color(red: 0.173, green: 0.141, blue: 0.094)
    static let paperMeta = Color(red: 0.541, green: 0.435, blue: 0.302)
    static let glow = Color(red: 1.0, green: 0.745, blue: 0.431)
    static let moon = Color(red: 0.910, green: 0.835, blue: 0.659)

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
    /// 窗口式挂枝：树上永远是 [windowStart, windowStart+16) 这一段。
    /// 滚轮先滚相机（自然滚动），滚到底/顶再逐档翻枝换挂
    private(set) var windowStart = 0
    private var totalItems = 0
    private var scrollAccum: CGFloat = 0
    private var viewportH: CGFloat = 500

    // MARK: 外部输入

    func setHover(_ x: CGFloat?) { hoverX = x }

    /// 滚轮：先滚相机看完整棵树；相机到边后继续滚 = 翻枝（换一批挂）。
    /// 新枝垂落本身就是翻页的物理反馈
    func scroll(by delta: CGFloat) {
        let maxCam = max(0, Curtain.contentBottomY - viewportH)
        if delta < 0 {
            if cameraTargetY < maxCam - 1 {
                cameraTargetY = min(maxCam, cameraTargetY - delta)
            } else if totalItems > Curtain.maxBranches {
                scrollAccum += delta
                while scrollAccum <= -24 { windowStart += 1; scrollAccum += 24 }
                clampWindow()
            }
        } else if delta > 0 {
            if cameraTargetY > 1 {
                cameraTargetY = max(0, cameraTargetY - delta)
            } else if windowStart > 0 {
                scrollAccum += delta
                while scrollAccum >= 24 { windowStart -= 1; scrollAccum -= 24 }
                clampWindow()
            }
        }
    }

    private func clampWindow() {
        let cap = min(totalItems, Curtain.maxBranches)
        windowStart = min(max(0, windowStart), max(0, totalItems - cap))
    }

    /// 方向键选到窗口外：把窗口挪到选中项可见。返回选中项的局部索引
    @discardableResult
    func ensureVisible(_ global: Int) -> Int {
        let cap = min(totalItems, Curtain.maxBranches)
        guard cap > 0 else { return 0 }
        if global < windowStart { windowStart = global }
        else if global >= windowStart + cap { windowStart = global - cap + 1 }
        clampWindow()
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

    /// 回到树冠（换搜索词 / 重开面板 = 一次新的「找」）：相机和挂枝窗口都回顶
    func snapCamera() {
        cameraTargetY = 0
        cameraY = 0
        windowStart = 0
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
        let cap = min(items.count, Curtain.maxBranches)
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
                    rope.nodes[rope.nodes.count - 1].px -= .random(in: -3...3)
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
            let angle = atan2(hang.x - prev.x, hang.y - prev.y) * 180 / .pi
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
    /// 绳从枝头「长」出来，重力把它拉直——这是生长动画的物理实现
    private func step(dt: TimeInterval, now: TimeInterval) {
        let dt2 = CGFloat(dt * dt)
        for rope in ropes.values {
            guard let spawned = rope.spawnedAt else { continue }
            let age = now - spawned.timeIntervalSinceReferenceDate
            let u = CGFloat(min(1, max(0, age / Curtain.unrollDuration)))
            let segNow = rope.fullSeg * (1 - pow(1 - u, 3))
            guard segNow > 0.5 else { continue }

            let n = rope.nodes
            var m = n
            for j in m.indices.dropFirst() {
                let vx = (m[j].x - m[j].px) * Curtain.verletDamping
                let vy = (m[j].y - m[j].py) * Curtain.verletDamping
                m[j].px = m[j].x
                m[j].py = m[j].y
                let wind = Motion.reduceMotion ? 0
                    : Curtain.windAmp * CGFloat(sin(now * 0.55 + Double(rope.phase) + Double(j) / Double(Curtain.nodes)))
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
                let a = rope.anchor
                m[0].x = a.x
                m[0].y = a.y
                m[0].px = a.x
                m[0].py = a.y
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
            .background(ScrollCatcher { delta in sim.scroll(by: delta) })
            .overlay(alignment: .bottomTrailing) {
                Text(L10n.curtainListHint)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Curtain.moon.opacity(0.7))
                    .padding(Rhythm.m)
            }
            .overlay(alignment: .center) {
                if items.isEmpty { emptyState }
            }
            .overlay(alignment: .bottom) {
                // 树是窗口式挂枝：还有更早的记录时给出去处
                if sim.windowStart + Curtain.maxBranches < items.count {
                    Text(L10n.curtainOlderHint)
                        .font(.system(size: Scale.meta))
                        .foregroundStyle(Curtain.moon.opacity(0.7))
                        .padding(Rhythm.m)
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
                sim.snapCamera()
                sim.beginGrowth()
            }
            .onChange(of: store.query) { _, _ in
                model.resetSelection()
                sim.snapCamera()
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

    /// 夜色 + 树冠暖光 + 月（世界坐标，随相机滚动）
    private func drawSky(ctx: GraphicsContext, size: CGSize, cameraY: CGFloat, width: CGFloat) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Curtain.nightBg))
        let glowY = 190 - cameraY
        let glowRect = CGRect(x: width * 0.5 - 210, y: glowY - 210, width: 420, height: 420)
        ctx.fill(Path(ellipseIn: glowRect), with: .color(Curtain.glow.opacity(0.05)))
        let moonY = 70 - cameraY
        let moonInner = CGRect(x: width * 0.85 - 17, y: moonY - 17, width: 34, height: 34)
        ctx.fill(Path(ellipseIn: moonInner), with: .color(Curtain.moon.opacity(0.10)))
        let moonOuter = CGRect(x: width * 0.85 - 26, y: moonY - 26, width: 52, height: 52)
        ctx.fill(Path(ellipseIn: moonOuter), with: .color(Curtain.moon.opacity(0.05)))
    }

    /// 树干（clip 从底部向上长）+ 横向枝线（每层一条，从树干向两侧伸展）
    private func drawTree(ctx: inout GraphicsContext, size: CGSize, cameraY: CGFloat, width: CGFloat) {
        let growth = sim.currentGrowth
        let count = min(max(items.count - sim.windowStart, 0), Curtain.maxBranches)
        let layoutWidth = sim.layoutWidth
        let trunkX = Curtain.spineXRatio * layoutWidth
        let crownY = Curtain.levelBaseY - 55

        let trunkGrowth = min(1, growth / Curtain.trunkPhase)
        if trunkGrowth > 0.01 {
            let clipRect = CGRect(x: 0, y: size.height * (1 - trunkGrowth),
                                  width: size.width, height: size.height * trunkGrowth)
            ctx.clip(to: Path(clipRect))
            let base = CGPoint(x: trunkX, y: Curtain.trunkBaseY - cameraY)
            let top = CGPoint(x: trunkX, y: crownY - cameraY)
            let mid = CGPoint(x: trunkX + 12, y: (Curtain.trunkBaseY + crownY) / 2 - cameraY)
            var trunk = Path()
            trunk.move(to: base)
            trunk.addQuadCurve(to: top, control: mid)
            ctx.stroke(trunk, with: .color(Curtain.inkBranch),
                       style: StrokeStyle(lineWidth: 14, lineCap: .round))
            // 侧根一笔，树才站得住
            var root = Path()
            root.move(to: CGPoint(x: trunkX, y: Curtain.trunkBaseY - 30 - cameraY))
            root.addQuadCurve(to: CGPoint(x: trunkX - 40, y: Curtain.trunkBaseY - 90 - cameraY),
                              control: CGPoint(x: trunkX - 24, y: Curtain.trunkBaseY - 50 - cameraY))
            ctx.stroke(root, with: .color(Curtain.inkBranch),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }

        // 枝线：每层一条横线（带一点交替的倾角，别像晾衣绳），
        // 按生长进度从树干向两侧伸出去
        let levelCount = (count + Curtain.lanes.count - 1) / Curtain.lanes.count
        for level in 0..<levelCount {
            let b = sim.branchProgress(level * Curtain.lanes.count,
                                       count: max(count, 1),
                                       growth: growth)
            guard b > 0.01 else { continue }
            let u = 1 - pow(1 - b, 2)
            let y = Curtain.tipY(level * Curtain.lanes.count)
            let tilt: CGFloat = level % 2 == 0 ? 7 : -7
            let edgeL = layoutWidth * 0.05
            let edgeR = layoutWidth * 0.95
            let lx = trunkX + (edgeL - trunkX) * u
            let rx = trunkX + (edgeR - trunkX) * u
            var line = Path()
            line.move(to: CGPoint(x: lx, y: y + tilt - cameraY))
            line.addLine(to: CGPoint(x: rx, y: y - tilt - cameraY))
            ctx.stroke(line, with: .color(Curtain.inkBranch.opacity(min(1, b * 2))),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }

        // 挂绳的木结（枝线长到位后出现在挂点）
        for tag in snapshotTagsForBeads(count: count, growth: growth) {
            let beadRect = CGRect(x: tag.x - 2.4, y: tag.y - 2.4, width: 4.8, height: 4.8)
            ctx.fill(Path(ellipseIn: beadRect), with: .color(Curtain.bead))
        }
    }

    /// 枝线 ≥90% 时挂点上的木结（世界坐标）
    private func snapshotTagsForBeads(count: Int, growth: CGFloat) -> [CGPoint] {
        var out: [CGPoint] = []
        for li in 0..<count {
            let b = sim.branchProgress(li, count: count, growth: growth)
            guard b > 0.9 else { continue }
            out.append(CGPoint(x: Curtain.tipX(li, width: sim.layoutWidth),
                               y: Curtain.tipY(li)))
        }
        return out
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
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Curtain.cardWidth - Rhythm.m * 2, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(item.summary)
                .font(.system(size: Scale.body))
                .lineLimit(2)
                .truncationMode(.tail)
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
    }
}
