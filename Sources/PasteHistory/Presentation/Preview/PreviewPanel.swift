import AppKit
import Combine
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
    private let mediaLoader: PreviewMediaLoader
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
    private let paperFollow = PaperPreviewFollow()
    private let paperScaleReturn = PaperScaleReturn()
    private var previewedID: UUID?
    private var paperReturnPose: PaperPose?
    private var paperSessionSize: NSSize?
    private var paperMagnification: CGFloat = 1
    private var gestureMagnification: CGFloat = 1
    private var needsFlightRetarget = false

    var window: NSPanel? { panel }
    var isVisible: Bool { (panel?.isVisible ?? false) && !isClosing }

    init(model: HistoryViewModel, owner: PanelController) {
        self.model = model
        self.mediaLoader = PreviewMediaLoader(imagesDirectory: model.store.imagesDirectory)
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
    private func openFromPaper(_ panel: NSPanel, continuing: Bool = false) {
        if !continuing {
            AnchorTrace.write("preview-input open pid=\(ProcessInfo.processInfo.processIdentifier) active=\(NSApp.isActive) key=\(panel.isKeyWindow)")
        }
        // Choose once per opening. Arrows move the sheet without resizing the
        // text container on every animation frame.
        paperFollow.cancel()
        paperScaleReturn.cancel()
        needsFlightRetarget = false
        if !continuing {
            paperSessionSize = Self.paperSize(for: model.current)
            paperMagnification = 1
            gestureMagnification = 1
        }
        (panel as? PaperPreviewPanel)?.beginPaperPinch()
        (panel.contentView as? PaperPreviewSurface)?.readingSize = paperSessionSize
        let target = targetFrame()
        let paper = owner?.previewPaper
        let origin = paper?.paperPose ?? paperReturnPose ?? PaperPose(frame: target)
        let image = paper?.paperFace?()
        previewedID = model.current?.id
        owner?.setExpandedPaper(previewedID)
        paperReturnPose = paper?.paperPose
        panel.setFrame(target, display: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        let expandedFace = snapshot(panel.contentView)
        let targetPose = readingPose(frame: target)
        paperFlight.animate(from: Motion.reduceMotion ? targetPose : origin, to: targetPose,
                            image: image, endImage: expandedFace, duration: Motion.reduceMotion ? 0.12 : Motion.paperOpenDuration,
                            opening: true) { [weak self, weak panel] in
            panel?.alphaValue = 1
            panel?.ignoresMouseEvents = false
            self?.followPaper()
        }
    }

    private func closeToPaper(_ panel: NSPanel) {
        (panel as? PaperPreviewPanel)?.endPaperPinch()
        let followVelocity = paperFollow.currentVelocity
        paperFollow.cancel()
        paperScaleReturn.cancel()
        if panel.isKeyWindow, owner?.previewAnchorVisible == true { owner?.makePanelKeyAgain() }
        let origin = readingPose(frame: panel.frame)
        let image = snapshot(panel.contentView)
        let destination = owner?.previewPaper?.paperPose ?? paperReturnPose ?? origin
        let paper = owner?.previewPaper?.paperFace?()
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        paperFlight.animate(from: origin, to: Motion.reduceMotion ? origin : destination,
                            image: image, endImage: paper, duration: Motion.reduceMotion ? 0.1 : Motion.paperCloseDuration,
                            opening: false, initialVelocity: followVelocity) { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1
            self.panel?.ignoresMouseEvents = false
            self.isClosing = false
            self.owner?.setExpandedPaper(nil)
        }
    }

    private func readingPose(frame: NSRect) -> PaperPose {
        let scale = frame.width / (paperSessionSize?.width ?? frame.width)
        return PaperPose(frame: frame, inset: IvoryPaperStyle.pinInset * scale)
    }

    private func snapshot(_ view: NSView?) -> NSImage? {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func closeImmediately() {
        (panel as? PaperPreviewPanel)?.endPaperPinch()
        closeGeneration += 1
        paperFlight.cancel()
        paperFollow.cancel()
        paperScaleReturn.cancel()
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
        if !paper {
            (panel.contentView as? PaperPreviewSurface)?.readingSize = nil
            (panel as? PaperPreviewPanel)?.endPaperPinch()
        }
        hosting?.rootView = PreviewContentView(model: model, mediaLoader: mediaLoader, paperStyle: paper)
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

    static func paperFrame(pin: NSPoint, visible: NSRect, size: NSSize = NSSize(width: 400, height: 247), magnification: CGFloat = 1) -> NSRect {
        let scale = min(1, max(1, visible.width - 24) / size.width, max(1, visible.height - 24) / size.height)
        let width = size.width * scale
        let height = size.height * scale
        let x = min(max(pin.x - width / 2, visible.minX + 12), visible.maxX - width - 12)
        let y = min(max(pin.y + IvoryPaperStyle.pinInset * magnification * scale - height, visible.minY + 12), visible.maxY - height - 12)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func followPaper() {
        guard owner?.previewBesideTree == true, isVisible, !isClosing,
              owner?.previewPaper != nil, let panel else { return }
        if paperFlight.visibleFrame != nil {
            // A new page may not have laid out its paper when selection changes.
            // Wait for that actual pin instead of flying to the tree's center.
            if needsFlightRetarget { openFromPaper(panel, continuing: true) }
            return
        }
        let target = targetFrame()
        paperReturnPose = owner?.previewPaper?.paperPose ?? paperReturnPose
        paperFollow.move(panel, to: target.origin)
    }

    private func buildPanel() {
        let view = PreviewContentView(model: model, mediaLoader: mediaLoader)
        let hosting = NSHostingController(rootView: view)
        hosting.safeAreaRegions = []
        self.hosting = hosting
        let panel = PaperPreviewPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = PaperPreviewSurface(document: hosting.view)
        panel.onMagnify = { [weak self] delta, phase in self?.magnifyPaper(by: delta, phase: phase) ?? false }
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
            let base = paperSessionSize ?? Self.paperSize(for: nil)
            return Self.paperFrame(pin: pin, visible: visible,
                size: NSSize(width: base.width * paperMagnification, height: base.height * paperMagnification),
                magnification: paperMagnification)
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

    private func magnifyPaper(by delta: CGFloat, phase: NSEvent.Phase) -> Bool {
        guard owner?.previewBesideTree == true, isVisible, !isClosing,
              let panel, let base = paperSessionSize else { return false }
        // Let an unfinished unfold complete before taking over its geometry.
        // Consume the gesture so descendants cannot start a second zoom layer.
        guard paperFlight.visibleFrame == nil else { return true }
        let screen = owner?.previewPaper.flatMap { paper in
            NSScreen.screens.first { $0.frame.intersects(paper.frame) }
        } ?? panel.screen ?? NSScreen.main
        guard let screen else { return true }
        let visible = screen.visibleFrame
        let screenMaximum = max(1, min((visible.width - 24) / base.width, (visible.height - 24) / base.height))
        let maximum = min(2, screenMaximum)
        if phase.contains(.began) {
            AnchorTrace.write("preview-pinch began delta=\(delta) scale=\(paperMagnification) maximum=\(maximum) key=\(panel.isKeyWindow)")
        }
        if phase.contains(.began) { gestureMagnification = paperMagnification }
        paperScaleReturn.cancel()
        gestureMagnification = min(maximum * 1.5, max(0.5, gestureMagnification * (1 + delta)))
        let bounded = min(maximum, max(1, gestureMagnification))
        // A little elastic travel at the limits, never beyond screen capacity.
        let elastic = min(screenMaximum, bounded + (gestureMagnification - bounded) * 0.12)
        applyPaperMagnification(elastic)
        if phase.contains(.ended) || phase.contains(.cancelled) {
            AnchorTrace.write("preview-pinch ended scale=\(bounded) width=\(panel.frame.width)")
            gestureMagnification = bounded
            paperScaleReturn.settle(from: paperMagnification, to: bounded) { [weak self] scale in
                self?.applyPaperMagnification(scale)
            }
        }
        return true
    }

    private func applyPaperMagnification(_ scale: CGFloat) {
        guard let panel, isVisible, !isClosing else { return }
        paperMagnification = scale
        paperFollow.cancel()
        panel.setFrame(targetFrame(), display: true)
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func syncAfterModelChange() {
        if isVisible, previewedID != model.current?.id {
            previewedID = model.current?.id
            if owner?.previewBesideTree == true { owner?.setExpandedPaper(previewedID) }
            paperReturnPose = owner?.previewPaper?.paperPose ?? paperReturnPose
            // Retarget an unfinished unfold from its visible sheet, never reveal
            // the full-size window at the previous card's location.
            needsFlightRetarget = paperFlight.visibleFrame != nil
        }
        guard (panel?.isVisible ?? false), !isClosing else { return }
        guard model.current != nil else {
            close()   // 列表被删空 / 过滤后无结果：预览不孤儿化
            return
        }
        followPaper()
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
