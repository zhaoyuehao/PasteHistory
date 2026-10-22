import AppKit
import SwiftUI

// MARK: - 参数

/// 线签帘（Tag Curtain）参数：每条剪贴记录是一张挂在顶部轨道上的纸签，
/// 新签挂得高、旧签沉下去；深度用透视投影表达，摆动由 verlet 绳物理驱动。
///
/// 设计原则与列表一致：阻尼感不是加出来的动画，是这个世界的物理——
/// 选中 = 踢一下绳末端（波沿绳传播），换签 = 相邻绳被反向带一下。
/// 「减少动态效果」时风与冲量关闭，绳静止垂直，但视图照常可用（降级不是关掉）。
enum Curtain {
    /// 透视焦距：深度 z 处的签缩放为 persp/(persp+z)，z ∈ [0, 460)
    static let persp: CGFloat = 900
    static let gravity: CGFloat = 1300
    /// verlet 速度保留系数（<1 即阻尼）
    static let verletDamping: CGFloat = 0.985
    /// 环境微风：绳常年轻微摆动，世界才是活的
    static let windAmp: CGFloat = 26
    /// 每根绳的节点数（末端节点是签，重物）
    static let nodes = 7
    /// 距离约束迭代次数
    static let iterations = 3

    // 冲量（单位：px/帧）
    static let kick: CGFloat = 9
    /// 连按方向键：冲量加大——连续移动恰恰最需要阻尼，不是关掉
    static let kickFast: CGFloat = 15
    static let hoverKick: CGFloat = 3.2
    /// 换签时旧签被反向带一下的余波
    static let wakeKick: CGFloat = 4

    /// 绳长随索引递增：时间维度 = 挂得越低。相机跟随选中项向下走
    static let lengthBase: CGFloat = 44
    static let lengthStep: CGFloat = 34
    /// 相机跟随（每帧 lerp）
    static let cameraLerp: CGFloat = 0.12
    /// 鼠标视差：近签动多、远签动少，深度才读得出来。工具面板的 3D 是
    /// 可感知但不可操纵的——要空间感，不要游戏相机
    static let parallax: CGFloat = 0.06
    /// 深度雾下限：后排签最淡到 0.5
    static let fogFloor: CGFloat = 0.5
    /// 纸签卡宽（未缩放）
    static let cardWidth: CGFloat = 176

    /// 冒烟：--view tags 强制线签帘（不写用户偏好）
    static var debugForce = false

    /// 深度：按索引确定性伪随机散布（137 = 质数步长，散点均匀不聚堆）
    static func depth(_ index: Int) -> CGFloat {
        CGFloat((index * 137 + 31) % 460)
    }

    /// 挂点 x：黄金角叶序散布，相邻索引的签不挨在一起
    static func anchorX(_ index: Int, width: CGFloat) -> CGFloat {
        let raw = width * (0.5 + 0.40 * sin(CGFloat(index) * 2.399963))
        return min(max(raw, 70), width - 70)
    }

    static func ropeLength(_ index: Int) -> CGFloat {
        lengthBase + CGFloat(index) * lengthStep
    }
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
}

struct CurtainWire: Identifiable {
    let id: String
    let title: String
    let y: CGFloat
}

/// 线签帘物理与投影。只在 SwiftUI 渲染线程（main）被 View 调用，
/// 不标 @MainActor 是因为 @State 默认值在 View 的非隔离 init 里创建
final class CurtainSim {
    struct Node { var x: CGFloat; var y: CGFloat; var px: CGFloat; var py: CGFloat }

    private final class Rope {
        let anchorX: CGFloat
        let segLen: CGFloat
        var nodes: [Node]
        let phase: CGFloat

        init(index: Int, width: CGFloat) {
            anchorX = Curtain.anchorX(index, width: width)
            let length = Curtain.ropeLength(index)
            segLen = length / CGFloat(Curtain.nodes)
            var ns: [Node] = []
            for j in 0..<Curtain.nodes {
                let y = CGFloat(j) * segLen
                ns.append(Node(x: anchorX, y: y, px: anchorX, py: y))
            }
            nodes = ns
            phase = CGFloat.random(in: 0..<(2 * .pi))
            // 出生即带一点初速度：整片帘一打开就是活的，不是静止后再被触发
            if !Motion.reduceMotion, let last = ns.indices.last {
                ns[last].px -= .random(in: -3...3)
            }
            nodes = ns
        }
    }

    private var ropes: [UUID: Rope] = [:]
    private var lastDate: Date?
    /// 相机纵向位置（世界坐标）：跟随选中签下移
    private var cameraY: CGFloat = 0
    private var cameraTargetY: CGFloat = 0
    /// 相机横向平移（视差）
    private var panX: CGFloat = 0
    private var hoverX: CGFloat?
    private let railY: CGFloat = 10

    // MARK: 外部输入

    func setHover(_ x: CGFloat?) { hoverX = x }

    /// 踢一下绳末端（速度冲量，px/帧）。选中 / 悬停都走这里
    func kick(id: UUID, _ velocity: CGFloat) {
        guard !Motion.reduceMotion, let rope = ropes[id], let last = rope.nodes.indices.last else { return }
        rope.nodes[last].px -= velocity
    }

    func updateCamera(index: Int) {
        cameraTargetY = max(0, Curtain.ropeLength(index) - 150)
    }

    /// 轨道线的纵向位置（Canvas 画轨道用；其余投影都在 frame() 里）
    var railScreenY: CGFloat { railY - cameraY }

    /// 回到帘顶（打开面板 / 换搜索词 = 一次新的「找」）
    func snapCamera() {
        cameraTargetY = 0
        cameraY = 0
    }

    // MARK: 每帧

    /// 对账（新记录挂新绳、消失的记录解绳）→ 物理步进 → 透视投影。
    /// 由 TimelineView(.animation) 每帧调用一次
    func frame(date: Date,
               items: [ClipItem],
               width: CGFloat,
               height: CGFloat,
               sectionStarts: [(index: Int, title: String)]) -> (tags: [CurtainPlacement], wires: [CurtainWire]) {
        let dt = min(0.05, lastDate.map { date.timeIntervalSince($0) } ?? 1 / 60)
        lastDate = date

        let ids = Set(items.map(\.id))
        let stale = ropes.keys.filter { !ids.contains($0) }
        stale.forEach { ropes.removeValue(forKey: $0) }
        for (i, item) in items.enumerated() where ropes[item.id] == nil {
            ropes[item.id] = Rope(index: i, width: width)
        }

        cameraY += (cameraTargetY - cameraY) * Curtain.cameraLerp
        let panTarget: CGFloat
        if Motion.reduceMotion {
            panTarget = 0
        } else {
            panTarget = hoverX.map { ($0 - width / 2) * Curtain.parallax } ?? 0
        }
        panX += (panTarget - panX) * 0.1

        step(dt: dt, now: date.timeIntervalSinceReferenceDate)

        var tags: [CurtainPlacement] = []
        let cx = width / 2
        for (i, item) in items.enumerated() {
            guard let rope = ropes[item.id] else { continue }
            let z = Curtain.depth(i)
            let s = Curtain.persp / (Curtain.persp + z)
            // 世界 → 屏幕：横向以画布中心为灭点收敛，纵向扣除相机位移
            let panX = self.panX
            let cameraY = self.cameraY
            let railY = self.railY
            let project: (Node) -> CGPoint = { n in
                CGPoint(x: cx + (n.x - cx) * s + panX * s,
                        y: railY + (n.y - cameraY) * s)
            }
            let hang = project(rope.nodes[rope.nodes.count - 1])
            // 视口裁剪：卡高约 80/scale，上下留裕量
            if hang.y < -140 || hang.y > height + 180 { continue }
            let prev = project(rope.nodes[rope.nodes.count - 2])
            let angle = atan2(hang.x - prev.x, hang.y - prev.y) * 180 / .pi
            tags.append(CurtainPlacement(
                id: item.id,
                index: i,
                depth: z,
                scale: s,
                fog: Curtain.fogFloor + (1 - Curtain.fogFloor) * s,
                angle: angle,
                hang: hang,
                path: rope.nodes.map(project)))
        }
        // 深的先画（在底下），浅的后画（盖上来）；选中项的 zIndex 在 View 里单独给
        tags.sort { $0.depth > $1.depth }

        var wires: [CurtainWire] = []
        for section in sectionStarts {
            let sy = railY + (Curtain.ropeLength(section.index) - 26) - cameraY
            if sy > 18, sy < height - 8 {
                wires.append(CurtainWire(id: section.title, title: section.title, y: sy))
            }
        }
        return (tags, wires)
    }

    /// verlet 积分 + 距离约束。末端节点是签（重物）：约束松弛时
    /// 绳节点让位 85%、签只让 15%——绳弯得起来，签才甩得出去
    private func step(dt: TimeInterval, now: TimeInterval) {
        let dt2 = CGFloat(dt * dt)
        for rope in ropes.values {
            var n = rope.nodes
            for j in n.indices.dropFirst() {
                let vx = (n[j].x - n[j].px) * Curtain.verletDamping
                let vy = (n[j].y - n[j].py) * Curtain.verletDamping
                n[j].px = n[j].x
                n[j].py = n[j].y
                let wind = Motion.reduceMotion ? 0
                    : Curtain.windAmp * CGFloat(sin(now * 0.6 + Double(rope.phase) + Double(j) / Double(Curtain.nodes)))
                n[j].x += vx + wind * dt2
                n[j].y += vy + Curtain.gravity * dt2
            }
            for _ in 0..<Curtain.iterations {
                for j in n.indices.dropFirst() {
                    let dx = n[j].x - n[j - 1].x
                    let dy = n[j].y - n[j - 1].y
                    let dist = (dx * dx + dy * dy).squareRoot()
                    guard dist > 0.0001 else { continue }
                    let diff = (dist - rope.segLen) / dist
                    let wa: CGFloat
                    let wb: CGFloat
                    if j == n.count - 1 { wa = 0.85; wb = 0.15 }
                    else if j == 1 { wa = 0; wb = 1 }
                    else { wa = 0.5; wb = 0.5 }
                    n[j - 1].x += dx * diff * wa
                    n[j - 1].y += dy * diff * wa
                    n[j].x -= dx * diff * wb
                    n[j].y -= dy * diff * wb
                }
                n[0].x = rope.anchorX
                n[0].y = 0
                n[0].px = rope.anchorX
                n[0].py = 0
            }
        }
    }
}

// MARK: - 视图

/// 剪贴历史的 3D「线签帘」视图：列表的兄弟视图（⌘L 互切），共享同一个
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

    /// 分组细线：除第一组外每个分组的起始条目（今天 / 昨天 / 更早 / 置顶）
    private var sectionStarts: [(index: Int, title: String)] {
        var out: [(index: Int, title: String)] = []
        for (i, section) in model.sections.enumerated() {
            if i > 0, let first = section.items.first {
                out.append((first.index, section.title))
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let snapshot = sim.frame(date: timeline.date,
                                         items: items,
                                         width: geo.size.width,
                                         height: geo.size.height,
                                         sectionStarts: sectionStarts)
                let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let selectedId = model.current?.id
                ZStack(alignment: .topLeading) {
                    curtainCanvas(snapshot: snapshot, selectedId: selectedId, height: geo.size.height)
                    ForEach(snapshot.tags) { p in
                        if let item = byId[p.id] {
                            TagCard(item: item, selected: p.id == selectedId)
                                .scaleEffect(p.scale, anchor: .top)
                                .rotationEffect(.degrees(p.angle), anchor: .top)
                                .offset(x: p.hang.x - Curtain.cardWidth / 2, y: p.hang.y)
                                .zIndex(p.id == selectedId ? 2000 : 1000 - p.depth)
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
            .overlay(alignment: .bottomTrailing) {
                Text(L10n.curtainListHint)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.meta)
                    .padding(Rhythm.m)
            }
            .overlay(alignment: .center) {
                if items.isEmpty { emptyState }
            }
            .onChange(of: model.safeSelection) { old, new in
                handleSelectionChange(old: old, new: new)
            }
            .onChange(of: model.presentationTick) { _, _ in sim.snapCamera() }
            .onChange(of: store.query) { _, _ in
                model.resetSelection()
                sim.snapCamera()
            }
        }
    }

    // MARK: Canvas（绳 / 轨道 / 分组线）

    private func curtainCanvas(snapshot: (tags: [CurtainPlacement], wires: [CurtainWire]),
                               selectedId: UUID?,
                               height: CGFloat) -> some View {
        Canvas { ctx, size in
            let wireStyle = StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            for wire in snapshot.wires {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: wire.y))
                line.addLine(to: CGPoint(x: size.width, y: wire.y))
                ctx.stroke(line, with: .color(Palette.meta.opacity(0.5)), style: wireStyle)
                ctx.draw(Text(wire.title)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.meta),
                    at: CGPoint(x: 24, y: wire.y - 8))
            }

            for tag in snapshot.tags {
                guard tag.path.count > 1 else { continue }
                var rope = Path()
                rope.move(to: tag.path[0])
                for point in tag.path.dropFirst() { rope.addLine(to: point) }
                let color: Color = tag.id == selectedId
                    ? .accentColor
                    : Color(NSColor.separatorColor).opacity(0.9)
                ctx.stroke(rope, with: .color(color), lineWidth: max(0.8, 1.5 * tag.scale))
            }

            // 轨道：相机下移后随世界滚出视口
            let railY = sim.railScreenY
            if railY > -2 && railY < height + 2 {
                var rail = Path()
                rail.move(to: CGPoint(x: 0, y: railY))
                rail.addLine(to: CGPoint(x: size.width, y: railY))
                ctx.stroke(rail, with: .color(Color(NSColor.labelColor).opacity(0.7)), lineWidth: 2)
            }
        }
    }

    // MARK: 交互

    private func handleSelectionChange(old: Int, new: Int) {
        guard !items.isEmpty else { return }
        let clamped = min(max(new, 0), items.count - 1)
        guard clamped >= 0, clamped < items.count else { return }
        let fast = Date().timeIntervalSince(model.lastMoveAt) < Motion.repeatThreshold
        let dir: CGFloat = new >= old ? 1 : -1
        // 旧签被反向带一下：视线离开的地方也要有余波
        if old != new, old >= 0, old < items.count, items[old].id != items[clamped].id {
            sim.kick(id: items[old].id, -dir * Curtain.wakeKick)
        }
        sim.kick(id: items[clamped].id, dir * (fast ? Curtain.kickFast : Curtain.kick))
        sim.updateCamera(index: clamped)
        if clamped >= items.count - 8 { store.loadMore() }
    }

    private var emptyState: some View {
        VStack(spacing: Rhythm.l) {
            Text(store.totalCount == 0 ? L10n.noHistory : L10n.noMatch)
                .font(.system(size: Scale.field, weight: .medium))
            Text(store.totalCount == 0 ? L10n.copySomething : L10n.tryAnother)
                .font(.system(size: Scale.body))
                .foregroundStyle(Palette.meta)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Rhythm.xxl)
    }
}

// MARK: - 纸签卡

/// 挂在绳末端的纸签：形状即类型（图片带缩略图、代码/文本/文件共用图标角标）。
/// 轻量是硬要求——TimelineView 每帧重建 ZStack，卡片的 body 必须便宜
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
                    .frame(width: Curtain.cardWidth - Rhythm.m * 2, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(item.summary)
                .font(.system(size: Scale.body))
                .lineLimit(2)
                .truncationMode(.tail)
            HStack(spacing: Rhythm.s) {
                Image(systemName: symbol)
                    .font(.system(size: Icon.mark))
                    .foregroundStyle(Palette.meta)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: Icon.mark))
                        .foregroundStyle(Palette.meta)
                }
                if let app = item.sourceApp {
                    Text(app)
                        .font(.system(size: Scale.meta))
                        .foregroundStyle(Palette.meta)
                        .lineLimit(1)
                }
                Text(RelativeTime.string(from: item.createdAt))
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.meta)
                Spacer(minLength: 0)
            }
        }
        .padding(Rhythm.m)
        .frame(width: Curtain.cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color(NSColor.separatorColor),
                              lineWidth: selected ? 1.5 : 0.5)
        )
    }
}
