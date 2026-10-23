import AppKit
import Combine
import ImageIO
import QuartzCore
import SwiftUI

// MARK: - 预览窗控制器

/// 空格 / ⌘Y 唤出的预览大窗。
///
/// 行为对齐 Finder 的 Quick Look（空格开关、↑↓ 实时换内容、Esc 两层退出），
/// 但窗体自建而不是用 QLPreviewPanel：
/// 1. 内容契约是自己定的——文本 / 图文 / 文件三种形态，外加文件丢失、
///    超长截断这些状态，系统模板覆盖不了；
/// 2. 动效必须走 Motion 令牌（开窗=面板出现、关窗=面板消失、切换=带方向位移）；
/// 3. nonactivatingPanel 不夺键盘焦点，↑↓ 空格 Esc 仍走面板的键监视器，零改动。
///
/// 生命周期挂在面板下面：面板收起它一定收起，预览窗从不单独存活。
/// 位置每次唤出按面板当前位置重算，不记忆——和面板同一条设计原则。
@MainActor
final class PreviewPanelController: NSObject, NSWindowDelegate {
    private let model: HistoryViewModel
    private weak var owner: PanelController?
    private var panel: NSPanel?
    private var hosting: NSHostingController<PreviewContentView>?
    /// 淡出进行中：窗口还没 orderOut，但逻辑上已经算关了
    private var isClosing = false
    /// 关窗动画的代际号：关到一半又开（连按空格）时，作废在排队的 orderOut
    private var closeGeneration = 0
    /// 在途的程序化 frame 动画数。**animator().setFrame 会成对发 live-resize
    /// 通知**（实测 WILL-START / DID-END 都会来，「程序化 setFrame 不经过
    /// live resize」只对非动画版本成立），windowDidEndLiveResize 必须忽略它们：
    /// 关窗缩回面板几何的那次动画会把 previewSize 记成「400 宽 × 面板当前高度」，
    /// 下一次开窗的目标尺寸就跟着面板的避让收缩一起变——「预览窗口一会大
    /// 一会小」的根因。连按空格时开/关动画重叠，用计数而不是布尔，
    /// 全部动画落地后才重新接受用户拖边
    private var frameAnimationsInFlight = 0
    /// 预览窗当前尺寸：默认 640×400（黄金矩形），用户拖边后记住（会话内）。
    /// 程序化 setFrame 不经过 live resize，关窗缩回锚点不会污染它
    private var previewSize = NSSize(width: Preview.width, height: Preview.height)
    private var sink: Any?
    private let paperFlight = PaperPreviewFlight()
    private var previewedID: UUID?
    private var paperReturnFrame: NSRect?
    private var paperSessionSize: NSSize?

    var window: NSPanel? { panel }
    var isVisible: Bool { (panel?.isVisible ?? false) && !isClosing }

    init(model: HistoryViewModel, owner: PanelController) {
        self.model = model
        self.owner = owner
        super.init()
        // 预览开着时列表发生了删除 / 清空 / 过滤：跟随下一条；列表空了就收窗，
        // 不做孤儿窗口。objectWillChange 是改前通知，转一道主队列再看，读到的一定是改后状态
        sink = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncAfterModelChange() }
    }

    func toggle() {
        isVisible ? close() : open()
    }

    func open() {
        guard model.current != nil else { return }   // 列表空不开窗
        if panel == nil { buildPanel() }
        guard let panel else { return }
        closeGeneration += 1
        isClosing = false
        panel.ignoresMouseEvents = false
        configureAppearance()
        if owner?.previewBesideTree == true {
            openFromPaper(panel)
            return
        }

        // 出现：从面板的几何长出来，就地把面板放大成预览——视线零移动。
        // （侧边落位会把视线拽到面板旁边，用户明确不要）
        // 「长出来」是幅度最大的动效：frame 插值本身就是那个在动的东西，
        // 内容 scale 就不再叠加了，叠两层会过
        let target = targetFrame()
        // 「减少动态效果」开启时跳过 frame 插值：直接就位 + 淡入（规范 5.5）
        if let anchor = owner?.previewAnchorFrame, anchor.width > 0, !Motion.reduceMotion,
           owner?.previewBesideTree != true {
            panel.setFrame(anchor, display: false)
        } else {
            panel.setFrame(target, display: false)
        }
        panel.alphaValue = 0
        // 不 makeKey：键盘焦点始终留在面板，↑↓ 空格 Esc 全都照旧走面板
        panel.orderFrontRegardless()
        frameAnimationsInFlight += 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !Motion.reduceMotion {
                panel.animator().setFrame(target, display: true)
            }
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.frameAnimationsInFlight = max(0, self.frameAnimationsInFlight - 1)
            }
        }
    }

    func close() {
        guard let panel, panel.isVisible, !isClosing else { return }
        closeGeneration += 1
        let generation = closeGeneration
        isClosing = true
        if owner?.previewBesideTree == true {
            closeToPaper(panel)
            return
        }
        // 预览窗可能因为点选文字拿到过键盘焦点：关窗前还给面板，
        // 否则面板看着开着、却没有键窗口，按键全部落空
        if panel.isKeyWindow, let owner, owner.previewAnchorVisible {
            owner.makePanelKeyAgain()
        }
        // 消失：缩回面板的几何 + 渐隐——开窗是「长出来」，关窗就是「收回去」，
        // 一来一回是同一趟旅程。普通的缩小消失会读出「弹回」很廉价，
        // 但缩回「我出发的地方」有语义，跟 Finder Quick Look 收回图标同款
        frameAnimationsInFlight += 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            // 「减少动态效果」开启时跳过缩回插值，只保留渐隐
            if let anchor = owner?.previewAnchorFrame, anchor.width > 0, !Motion.reduceMotion,
           owner?.previewBesideTree != true {
                panel.animator().setFrame(anchor, display: true)
            }
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.frameAnimationsInFlight = max(0, self.frameAnimationsInFlight - 1)
                guard self.closeGeneration == generation, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.isClosing = false
            }
        }
    }

    /// Animate a lightweight paper snapshot, not a resizing text layout. The
    /// actual preview stays at its final size; arrow navigation never queues flights.
    private func openFromPaper(_ panel: NSPanel) {
        // Choose once per opening. Arrows move the sheet without resizing the
        // text container on every animation frame.
        paperSessionSize = Self.paperSize(for: model.current)
        let target = targetFrame()
        let paper = owner?.previewPaper
        let origin = paperFlight.visibleFrame ?? paper?.frame ?? paperReturnFrame ?? target
        let image = (paper?.contentView as? TreePaperSurface)?.paperImage()
        previewedID = model.current?.id
        owner?.setExpandedPaper(previewedID)
        paperReturnFrame = paper?.frame
        panel.setFrame(target, display: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        paperFlight.animate(from: Motion.reduceMotion ? target : origin, to: target,
                            image: image, duration: Motion.reduceMotion ? 0.12 : Motion.paperOpenDuration,
                            opening: true) { [weak panel] progress in
            panel?.alphaValue = max(0, (progress - 0.75) / 0.25)
        } completion: { [weak panel] in
            panel?.alphaValue = 1
            panel?.ignoresMouseEvents = false
        }
    }

    private func closeToPaper(_ panel: NSPanel) {
        if panel.isKeyWindow, owner?.previewAnchorVisible == true { owner?.makePanelKeyAgain() }
        let origin = paperFlight.visibleFrame ?? panel.frame
        let image = paperFlight.visibleImage ?? snapshot(panel.contentView)
        let destination = owner?.previewPaper?.frame ?? paperReturnFrame ?? panel.frame
        let paper = (owner?.previewPaper?.contentView as? TreePaperSurface)?.paperImage()
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        paperFlight.animate(from: origin, to: Motion.reduceMotion ? origin : destination,
                            image: image, endImage: paper, duration: Motion.reduceMotion ? 0.1 : Motion.paperCloseDuration,
                            opening: false, progress: { _ in }) { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1
            self.panel?.ignoresMouseEvents = false
            self.isClosing = false
            self.owner?.setExpandedPaper(nil)
        }
    }

    private func snapshot(_ view: NSView?) -> NSImage? {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func closeImmediately() {
        closeGeneration += 1
        paperFlight.cancel()
        owner?.setExpandedPaper(nil)
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        panel?.ignoresMouseEvents = false
        isClosing = false
    }

    // MARK: - 构建

    private func configureAppearance() {
        guard let panel else { return }
        let paper = owner?.previewBesideTree == true
        hosting?.rootView = PreviewContentView(model: model, paperStyle: paper)
        panel.styleMask = paper ? [.borderless, .nonactivatingPanel]
            : [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable]
        panel.minSize = paper ? NSSize(width: 1, height: 1) : NSSize(width: Preview.minWidth, height: Preview.minHeight)
        panel.isMovable = !paper
        panel.isMovableByWindowBackground = !paper
        panel.isOpaque = !paper
        panel.backgroundColor = paper ? .clear : .windowBackgroundColor
        panel.appearance = paper ? NSAppearance(named: .aqua) : nil
        panel.hasShadow = true
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = paper ? NSColor.clear.cgColor : nil
        panel.contentView?.layer?.cornerRadius = paper ? IvoryPaperStyle.radius : 0
        panel.contentView?.layer?.masksToBounds = paper
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    /// Keep the hole on the branch while the paper unfolds below it. Only
    /// screen-edge clamping may shift this point; never choose a side of the tree.
    static func paperSize(for item: ClipItem?) -> NSSize {
        let sizes = [NSSize(width: 340, height: 210), NSSize(width: 400, height: 247), NSSize(width: 480, height: 297)]
        guard let item else { return sizes[1] }
        switch item.kind {
        case .text:
            let text = String((item.text ?? "").prefix(3000)) as NSString
            for size in sizes {
                let measured = text.boundingRect(with: NSSize(width: size.width - 42, height: 1000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: NSFont.systemFont(ofSize: 15)]).height
                if ceil(measured) + 84 <= size.height { return size }
            }
            return sizes[2]
        case .files: return (item.filePaths?.count ?? 0) > 3 ? sizes[2] : sizes[1]
        case .image: return sizes[2]
        }
    }

    static func paperFrame(pin: NSPoint, visible: NSRect, size: NSSize = NSSize(width: 400, height: 247)) -> NSRect {
        let scale = min(1, max(1, visible.width - 24) / size.width, max(1, visible.height - 24) / size.height)
        let width = size.width * scale
        let height = size.height * scale
        let x = min(max(pin.x - width / 2, visible.minX + 12), visible.maxX - width - 12)
        let y = min(max(pin.y + IvoryPaperStyle.pinInset - height, visible.minY + 12), visible.maxY - height - 12)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func followPaper() {
        guard owner?.previewBesideTree == true, isVisible, !isClosing,
              paperFlight.visibleFrame == nil, owner?.previewPaper != nil, let panel else { return }
        let target = targetFrame()
        let current = panel.frame
        let positionDelta: CGFloat = abs(current.minX - target.minX) + abs(current.minY - target.minY)
        let sizeDelta: CGFloat = abs(current.width - target.width) + abs(current.height - target.height)
        guard positionDelta + sizeDelta > 2 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.8, 0.25, 1.1)
            panel.animator().setFrameOrigin(target.origin)
        }
    }

    private func buildPanel() {
        let view = PreviewContentView(model: model)
        let hosting = NSHostingController(rootView: view)
        hosting.safeAreaRegions = []
        self.hosting = hosting
        let panel = PaperPreviewPanel(contentViewController: hosting)
        // 与面板同一套窗口语言：透明标题栏、藏红绿灯、可拖动背景——一张卡片，不是一扇窗户
        panel.styleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // 标题不画出来，但读屏要有名字——VO 念「Untitled」等于没念
        panel.title = L10n.previewTitle
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        // 比面板高一级：同层时 orderFront 的先后才不会互相盖
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.setContentSize(NSSize(width: Preview.width, height: Preview.height))
        // 可拖边调整（会话内记住）；下限 400×247 ≈ 默认 ÷ φ²，缩到底仍在黄金系
        panel.minSize = NSSize(width: Preview.minWidth, height: Preview.minHeight)
        panel.maxSize = NSSize(width: 940, height: 1200)
        panel.delegate = self
        self.panel = panel
    }

    // MARK: - 落位

    /// 目标几何：**以面板为中心就地放大**——盖在面板上方，与面板同心。
    /// 用户的视线就在面板上，侧边落位会把视线拽走（用户明确不要）。
    /// 面板中心拿不到才退当前屏居中。屏幕放不下就收高，不挪中心。
    private func targetFrame() -> NSRect {
        let paper = owner?.previewBesideTree == true ? owner?.previewPaper : nil
        let anchor = paper?.frame ?? owner?.previewAnchorFrame
        let screen = anchor.flatMap { a in
            NSScreen.screens.first { $0.frame.intersects(a) }
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(x: 0, y: 0, width: previewSize.width, height: previewSize.height)
        }
        let visible = screen.visibleFrame
        if owner?.previewBesideTree == true {
            let pin = paper?.paperPin ?? anchor.map { NSPoint(x: $0.midX, y: $0.maxY - IvoryPaperStyle.pinInset) }
                ?? NSPoint(x: visible.midX, y: visible.midY)
            return Self.paperFrame(pin: pin, visible: visible, size: paperSessionSize ?? Self.paperSize(for: nil))
        }

        // 窗高：用户拖边后的尺寸或默认 640×400（黄金矩形）；塞不下收到恰好放得下
        let wanted = previewSize.height
        let available = visible.height - Preview.margin * 2
        let height = min(wanted, max(Preview.minHeight, available))
        let width = previewSize.width

        // 同心：中心对中心，视线在面板的哪里，预览就在哪里
        let cx = anchor.map { $0.midX } ?? visible.midX
        let cy = anchor.map { $0.midY } ?? visible.midY
        var x = cx - width / 2
        var y = cy - height / 2
        // 夹回屏幕内：挪的是边缘，不是中心
        x = min(max(x, visible.minX + Preview.margin),
                visible.maxX - Preview.margin - width)
        y = min(max(y, visible.minY + Preview.margin),
                visible.maxY - Preview.margin - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - 跟随列表

    private func syncAfterModelChange() {
        if isVisible, previewedID != model.current?.id {
            previewedID = model.current?.id
            if owner?.previewBesideTree == true { owner?.setExpandedPaper(previewedID) }
            paperReturnFrame = owner?.previewPaper?.frame ?? paperReturnFrame
            // A new selection takes over immediately; don't show a stale flying card.
            if paperFlight.visibleFrame != nil {
                paperFlight.cancel()
                panel?.alphaValue = 1
                panel?.ignoresMouseEvents = false
            }
        }
        guard (panel?.isVisible ?? false), !isClosing else { return }
        guard model.current != nil else {
            close()   // 列表被删空 / 过滤后无结果：预览不孤儿化
            return
        }
        // 窗高不随内容形态切换（默认 640×400 黄金矩形，用户拖边后为其尺寸）——
        // 条目增删后预览跟随下一条，列表空了收窗，窗体几何稳定
    }

    // MARK: - NSWindowDelegate

    /// 用户拖边结束：记住尺寸（会话内）。程序化 setFrame/setContentSize
    /// 不经过这里；**但 animator().setFrame 会**（实测成对触发 WILL-START /
    /// DID-END），所以还要看在途动画计数——开/关窗动画的终点帧不是用户选择，
    /// 记下来 previewSize 就被面板几何污染（预览一会大一会小的根因）
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        guard frameAnimationsInFlight == 0, owner?.previewBesideTree != true else { return }
        previewSize = panel.frame.size
    }

    func windowDidResignKey(_ notification: Notification) {
        guard owner?.previewBesideTree != true else { return }
        // 焦点的去向要等一拍才问得出（makeKey 交接有时序）：
        // 用户点回面板不算离开；真去了别的应用，整组一起收
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !self.isClosing else { return }
            if NSApp.keyWindow == nil {
                self.owner?.dismissAllFromPreview()
            }
        }
    }
}

/// A bounded, non-key window tracks the moving sheet. Empty desktop space
/// remains click-through; the visible moving sheet consumes clicks during flight.
@MainActor
private final class PaperPreviewFlight {
    private var window: NSPanel?
    private var timer: Timer?
    private var imageView: NSImageView?
    var visibleFrame: NSRect? { window?.isVisible == true ? window?.frame : nil }
    var visibleImage: NSImage? { visibleFrame == nil ? nil : imageView?.image }

    func cancel() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil)
    }

    func animate(from: NSRect, to: NSRect, image: NSImage?, endImage: NSImage? = nil,
                 duration: Double, opening: Bool, progress: @escaping (CGFloat) -> Void,
                 completion: @escaping () -> Void) {
        cancel()
        let panel = NSPanel(contentRect: from, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "纸签预览过渡"
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let host = NSView(frame: NSRect(origin: .zero, size: from.size))
        if opening {
            host.wantsLayer = true
            host.layer?.backgroundColor = IvoryPaperStyle.fill.cgColor
            host.layer?.cornerRadius = IvoryPaperStyle.radius
            host.layer?.borderColor = IvoryPaperStyle.edge.cgColor
            host.layer?.borderWidth = 1.5
        }
        let sheet = NSImageView(frame: host.bounds)
        sheet.image = image
        // Unfold the sheet without stretching its short excerpt into giant text.
        sheet.imageScaling = opening ? .scaleProportionallyDown : .scaleAxesIndependently
        sheet.imageAlignment = opening ? .alignTop : .alignCenter
        sheet.autoresizingMask = [.width, .height]
        host.addSubview(sheet)
        let destination = NSImageView(frame: host.bounds)
        destination.image = endImage; destination.imageScaling = .scaleAxesIndependently
        destination.autoresizingMask = [.width, .height]; destination.alphaValue = 0
        host.addSubview(destination)
        panel.contentView = host
        window = panel; imageView = sheet
        panel.orderFrontRegardless()
        let start = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak panel] timer in
            MainActor.assumeIsolated {
            guard let self, let panel else { timer.invalidate(); return }
            let t = min(1, CGFloat((CACurrentMediaTime() - start) / duration))
            let p = Motion.reduceMotion ? t : Motion.paperProgress(t, opening: opening)
            let rect = NSRect(x: from.minX + (to.minX-from.minX)*p,
                              y: from.minY + (to.minY-from.minY)*p,
                              width: from.width + (to.width-from.width)*p,
                              height: from.height + (to.height-from.height)*p)
            panel.setFrame(rect, display: true)
            if opening { panel.alphaValue = 1 - max(0, (t-0.75)/0.25) }
            else if endImage != nil {
                sheet.alphaValue = 1-t; destination.alphaValue = t
                panel.alphaValue = 1 - max(0, (t-0.8)/0.2)
            } else { panel.alphaValue = 1-t }
            progress(t)
            if t >= 1 {
                self.cancel()
                completion()
            }
            }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
}

private final class PaperPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 预览内容

struct PreviewContentView: View {
    @ObservedObject var model: HistoryViewModel
    var paperStyle = false

    /// 切换动画的方向：+1 新内容从下浮入（按 ↓），-1 从上（按 ↑）
    @State private var direction: Int = 1
    @State private var contentOffset: CGFloat = 0
    @State private var contentOpacity: Double = 1
    /// 驱动切换动画的内容身份。model 的变化不经过我们的事务，
    /// 切换动画必须由这里的 withAnimation 挂上去
    @State private var displayedID: UUID?
    /// 边界橡皮筋：与列表共用同一个 bounceTick，两边同步下沉再弹回
    @State private var bounceOffset: CGFloat = 0
    /// 原图（后台降采样解码完）；解码期间先用 DB 缩略图顶着，到了原位替换
    @State private var fullImage: NSImage?
    /// 原图的原始像素尺寸（读文件头，不解码整图）
    @State private var originalPixels: CGSize?
    /// 预览图文件字节数（与像素尺寸一样在后台读，body 里不再做磁盘 I/O）
    @State private var fileBytes: Int?
    /// 当前条目对应的预览图文件：`previewImageURL` 里有 fileExists（磁盘 I/O），
    /// 以前散在 headerMeta / filesContent 里每次 body 都 stat 一遍，
    /// 现在只在切换条目时解析一次
    @State private var imageURL: URL?

    /// 原图解码缓存（按文件路径）：↑↓↑ 来回切同一条不再每次重新解码，
    /// 也不会再闪一次低清缩略图
    private static let previewCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// 正在展示的条目：按 displayedID 找回，而不是直接读 model.current——
    /// 后者在切换的那一拍已经指向新条目，会跳过过渡直接换内容
    private var displayedItem: ClipItem? {
        guard let displayedID else { return model.current }
        return model.results.first { $0.id == displayedID } ?? model.current
    }

    var body: some View {
        if let item = displayedItem {
            VStack(spacing: 0) {
                if paperStyle { paperHeader(item) }
                else { header(item); hairline }
                ZStack {
                    content(item)
                        // 身份变化驱动切换：旧内容淡出，新内容从按键方向浮入。
                        // 不用交叉淡化——中间没有任何东西在移动，人眼几乎无感，
                        // 和选中高亮用 matchedGeometryEffect 是同一个理由
                        .id(displayedID)
                        .offset(y: contentOffset)
                        .opacity(contentOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // 撞到顶/底：预览内容与面板列表一起被推——像一个整体
                .offset(y: bounceOffset)
                if paperStyle {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(IvoryPaperStyle.meta))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Rhythm.xxl).padding(.bottom, Rhythm.xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .background(Color(paperStyle ? IvoryPaperStyle.fill : NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: paperStyle ? IvoryPaperStyle.radius : 0))
            .overlay {
                if paperStyle {
                    RoundedRectangle(cornerRadius: IvoryPaperStyle.radius)
                        .strokeBorder(Color(IvoryPaperStyle.edge), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .task(id: model.current?.id) {
                await step(to: model.current)
            }
            .onChange(of: model.bounceTick) { _, _ in
                // 与 HistoryView 同一套规则：弹簧没停稳不叠推；「减少动态效果」
                // 开启时整段推送跳过。先瞬间推出去，再让弹簧拉回来
                guard !Motion.reduceMotion, bounceOffset == 0 else { return }
                bounceOffset = CGFloat(model.bounceDirection) * Motion.bounceDistance
                withAnimation(Motion.bounce) { bounceOffset = 0 }
            }
        }
    }

    /// 条目变化 = 切换动画 + 原图加载，两个动作挂在同一次身份变化上
    private func step(to item: ClipItem?) async {
        guard let item else { return }
        // 预览图路径一次解析：里面有 fileExists，别再让 body 反复查
        imageURL = previewImageURL(item)
        if displayedID == nil {
            // 首次呈现：直接就位，不做切换动画
            displayedID = item.id
        } else if displayedID != item.id {
            direction = Self.moveDirection(from: displayedID, to: item.id, in: model.results)
            // 连按压短弹簧，不是关掉——连续移动恰恰最需要阻尼
            // Replace the old view immediately: rapid navigation must not retain several
            // expensive text layouts in an outgoing transition.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedID = item.id
                contentOffset = Motion.reduceMotion ? 0 : CGFloat(direction) * Preview.slideDistance
                contentOpacity = Motion.reduceMotion ? 0.6 : 1
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(Motion.selectionFast) {
                contentOffset = 0
                contentOpacity = 1
            }
        }
        await loadPreviewImage(item)
    }

    // MARK: - 图片加载

    private func loadPreviewImage(_ item: ClipItem) async {
        guard let url = imageURL else {
            fullImage = nil
            originalPixels = nil
            fileBytes = nil
            return
        }
        // 先清掉上一条的原图：不能让旧图在新条目上闪一帧
        fullImage = nil
        originalPixels = nil
        fileBytes = nil
        let id = item.id

        // 刚看过的图直接复用解码结果：低清缩略图都不用闪
        let cached = Self.previewCache.object(forKey: url.path as NSString)
        if let cached { fullImage = cached }

        // 出发前先看自己有没有被更新的按键作废：detached 任务不响应取消，
        // 以前每次按键都派一个解码跑到底、结果又被丢弃——连按时解码任务
        // 堆在一起抢 CPU，正是预览跟着列表快速切换时风扇转起来的来源
        guard !Task.isCancelled else { return }
        let needsDecode = cached == nil
        // Coalesce key repeats before starting work that ImageIO cannot cancel.
        if needsDecode {
            do { try await Task.sleep(for: .milliseconds(55)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        // 降采样解码放后台：预览窗就 640 宽，8000px 整图进内存是风扇测试
        let decoded = await Task.detached(priority: .userInitiated) {
            (image: needsDecode ? Self.downsampledImage(at: url, maxPixel: Preview.maxImagePixel) : nil,
             pixels: Self.pixelSize(at: url),
             bytes: Self.fileBytes(at: url))
        }.value
        // 解码期间可能已经切到下一条：别把旧图盖到新内容上
        guard !Task.isCancelled, displayedID == id else { return }
        if let image = decoded.image {
            Self.previewCache.setObject(image, forKey: url.path as NSString,
                                        cost: Int(image.size.width * image.size.height * 4))
            fullImage = image
        }
        originalPixels = decoded.pixels
        fileBytes = decoded.bytes
    }

    private func previewImageURL(_ item: ClipItem) -> URL? {
        switch item.kind {
        case .image:
            guard let name = item.imageFile else { return nil }
            let url = ClipStore.shared.imagesDirectory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .files:
            // 微信等应用复制的 jpg 以文件形式进剪贴板：kind 是 .files，内容其实是图
            guard let path = item.firstImageFilePath,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        case .text:
            return nil
        }
    }

    /// ImageIO 降采样解码：只解出预览需要的尺寸
    nonisolated private static func downsampledImage(at url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// 只读文件头拿原始像素尺寸，不解码
    nonisolated private static func pixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return CGSize(width: w, height: h)
    }

    private static func moveDirection(from old: UUID?, to new: UUID, in results: [ClipItem]) -> Int {
        guard let old,
              let oldIndex = results.firstIndex(where: { $0.id == old }),
              let newIndex = results.firstIndex(where: { $0.id == new }) else { return 1 }
        return newIndex > oldIndex ? 1 : -1
    }

    // MARK: - 头部

    /// 标题栏即元信息：类型图标 + 摘要 + 来源·时间·尺寸。
    /// 这三样正是扫列表时的抓手，大窗里保持在场。切换时头部保持稳定，只有内容在走
    private func paperHeader(_ item: ClipItem) -> some View {
        VStack(spacing: 0) {
            Circle().fill(Color(IvoryPaperStyle.meta).opacity(0.7))
                .frame(width: 3.4, height: 3.4).padding(.top, 5.3)
            HStack {
                let index = model.results.firstIndex { $0.id == item.id } ?? 0
                Text(String(format: "%02d", index + 1) + (item.pinned ? " · ↟ " : " · ") + (item.sourceApp ?? "—"))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .foregroundStyle(Color(IvoryPaperStyle.meta))
            .padding(.horizontal, Rhythm.xxl).padding(.top, Rhythm.l).padding(.bottom, Rhythm.m)
        }
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.kindSymbol(item.kind))
                .font(.system(size: Icon.action))
                .foregroundStyle(Palette.meta)
                .accessibilityLabel(item.kind == .text ? L10n.text : item.kind == .image ? L10n.image : L10n.files)
            Text(item.summary)
                .font(.system(size: Scale.body, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(headerMeta(item))
                .font(.system(size: Scale.meta))
                .foregroundStyle(Palette.meta)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, Rhythm.xl)
        .frame(height: 44)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func headerMeta(_ item: ClipItem) -> String {
        var parts: [String] = []
        if let app = item.sourceApp { parts.append(app) }
        parts.append(RelativeTime.string(from: item.createdAt))
        switch item.kind {
        case .text:
            parts.append(L10n.charCount((item.text ?? "").count))
        case .image:
            // 像素尺寸 / 字节数由后台解码回填（originalPixels / fileBytes），
            // 没到就先不显示，body 里不做磁盘 I/O
            if let pixels = originalPixels {
                parts.append(L10n.pixelSize(Int(pixels.width), Int(pixels.height)))
            }
            if let bytes = fileBytes {
                parts.append(Self.formatBytes(bytes))
            }
        case .files:
            parts.append(L10n.fileCount((item.filePaths ?? []).count))
        }
        return parts.joined(separator: " · ")
    }

    private static func kindSymbol(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    nonisolated private static func fileBytes(at url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    private static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// 全界面唯一一条线（与面板同款）
    private var hairline: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor).opacity(0.6))
            .frame(height: 0.5)
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text: textContent(item)
        case .image: imageContent(item)
        case .files: filesContent(item)
        }
    }

    private func textContent(_ item: ClipItem) -> some View {
        let text = item.text ?? ""
        let isTruncated = text.count > Preview.maxTextLength
        return PreviewTextView(text: String(text.prefix(Preview.maxTextLength)), identity: item.id, paperStyle: paperStyle)
        .overlay(alignment: .bottom) {
            if isTruncated { truncatedBar }
        }
    }

    private var truncatedBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: Icon.action))
            Text(L10n.previewTruncated)
                .font(.system(size: Scale.meta))
        }
        .foregroundStyle(Palette.meta)
        .padding(.horizontal, Rhythm.xl)
        .padding(.vertical, Rhythm.l)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 1)
        )
        .padding(.bottom, Rhythm.xl)
    }

    private func imageContent(_ item: ClipItem) -> some View {
        let caption = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(spacing: 0) {
            imageStage
            if !caption.isEmpty {
                // 图文记录：文字部分是复制的本意——图先看清，文字原文在下
                hairline
                ScrollView {
                    Text(caption)
                        .font(.system(size: Scale.body))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Rhythm.xl)
                }
                // 递归 φ 分割：说明区 153 = 400×0.382，图区 247 ≈ 153×φ，整窗 ≈ 153×φ²
                .frame(maxHeight: Preview.captionHeight)
            }
        }
    }

    private func filesContent(_ item: ClipItem) -> some View {
        let paths = item.filePaths ?? []
        return VStack(spacing: 0) {
            // 首个图片文件升格为预览主体（面板行已是这条判断，大窗沿用）
            if imageURL != nil {
                imageStage
                    .overlay(alignment: .bottom) {
                        if let meta = fileImageMeta(item) {
                            Text(meta)
                                .font(.system(size: Scale.meta))
                                .foregroundStyle(Palette.meta)
                                .padding(.bottom, 12)
                        }
                    }
                hairline
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(paths, id: \.self) { path in
                        PreviewFileRow(path: path)
                    }
                }
                .padding(Rhythm.xl)
            }
        }
    }

    private var imageStage: some View {
        ZStack {
            if let image = fullImage ?? displayedItem?.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(Rhythm.xxl)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34))   // Fib 档（与主列表缩略图同档），体系外尺寸归零
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 文件形态里首个图片文件的元信息：名称 · 像素尺寸 · 大小。
    /// 像素尺寸 / 字节数都来自后台回填的 state，不在 body 里碰磁盘
    private func fileImageMeta(_ item: ClipItem) -> String? {
        guard let url = imageURL else { return nil }
        var parts: [String] = [url.lastPathComponent]
        if let pixels = originalPixels {
            parts.append(L10n.pixelSize(Int(pixels.width), Int(pixels.height)))
        }
        if let bytes = fileBytes {
            parts.append(Self.formatBytes(bytes))
        }
        return parts.joined(separator: " · ")
    }
}

/// NSTextView lays out visible paragraphs on demand. A large clip no longer
/// builds a 100,000-character SwiftUI selectable Text during every key repeat.
private struct PreviewTextView: NSViewRepresentable {
    let text: String
    let identity: UUID
    var paperStyle = false
    final class Coordinator { var identity: UUID?; var text = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: paperStyle ? 15 : Scale.body)
        view.textColor = paperStyle ? IvoryPaperStyle.ink : .labelColor
        view.textContainerInset = NSSize(width: Rhythm.xxl, height: paperStyle ? Rhythm.l : Rhythm.xxl)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.bounds.width, height: .greatestFiniteMagnitude)
        view.layoutManager?.allowsNonContiguousLayout = true
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let view = scroll.documentView as? NSTextView {
            view.font = .systemFont(ofSize: paperStyle ? 15 : Scale.body)
            view.textColor = paperStyle ? IvoryPaperStyle.ink : .labelColor
            view.textContainerInset = NSSize(width: Rhythm.xxl, height: paperStyle ? Rhythm.l : Rhythm.xxl)
        }
        guard context.coordinator.identity != identity || context.coordinator.text != text,
              let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.identity = identity
        context.coordinator.text = text
        view.string = text
        view.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - 文件行

/// 预览里的单个文件：图标 + 名称 + 大小/所在目录。
/// 文件已被移动或删除就置灰并说明——比渲染一个空白占位诚实
private struct PreviewFileRow: View {
    let path: String

    @State private var hovered = false
    /// 图标与大小/存在性都要碰磁盘（NSWorkspace.icon 还可能走 icon services），
    /// 以前全在 body 里、每次重渲染都来一遍；现在行出现时取一次。
    /// exists 初始按「在」处理，避免绝大多数正常行闪一帧灰色
    @State private var icon: NSImage?
    @State private var sizeText: String?
    @State private var exists = true

    var body: some View {
        HStack(spacing: Rhythm.xl) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: Scale.body))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Rhythm.m) {
                    if exists {
                        if let sizeText {
                            Text(sizeText)
                        }
                        // 在：给所在目录；不在了：给完整路径，用户才知道去哪找
                        Text((path as NSString).deletingLastPathComponent)
                    } else {
                        Text(path)
                    }
                }
                .font(.system(size: Scale.meta))
                .foregroundStyle(Palette.meta)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !exists {
                Text(L10n.fileMissing)
                    .font(.system(size: Scale.meta))
                    .foregroundStyle(Palette.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.09))   // 静态块 = chip 档
                    )
                    .fixedSize()
            }
        }
        .padding(.horizontal, Rhythm.l)
        .padding(.vertical, Rhythm.l)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(hovered ? 0.10 : 0))   // 悬停 = 承诺，比静态 chip（0.09）深一档
        )
        .opacity(exists ? 1 : 0.55)
        .animation(Motion.hover, value: hovered)
        .onHover { hovered = $0 }
        .task { await loadDiskInfo() }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 34, height: 34)   // Fib 档，与主列表缩略图同档
        } else {
            Color.clear
                .frame(width: 34, height: 34)
        }
    }

    /// stat 放后台；NSWorkspace.icon 不保证线程安全，留在主线程取
    /// （每个身份只取一次，icon services 自带缓存，代价可忽略）
    private func loadDiskInfo() async {
        let (fileExists, size) = await Task.detached(priority: .userInitiated) {
            let exists = FileManager.default.fileExists(atPath: path)
            return (exists, exists ? Self.fileSize(path) : nil)
        }.value
        guard !Task.isCancelled else { return }
        exists = fileExists
        sizeText = size
        icon = NSWorkspace.shared.icon(forFile: path)
    }

    nonisolated private static func fileSize(_ path: String) -> String? {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
              bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
