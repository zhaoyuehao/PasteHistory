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
final class PreviewPanelController: NSObject {
    private let model: HistoryViewModel
    private let mediaLoader: PreviewMediaLoader
    private weak var owner: PanelController?
    private var panel: NSPanel?
    private var hosting: NSHostingController<PreviewContentView>?
    /// 淡出进行中：窗口还没 orderOut，但逻辑上已经算关了
    private var isClosing = false
    private var sink: Any?
    private let paperFlight = PaperPreviewFlight()
    private let paperFollow = PaperPreviewFollow()
    private let paperScaleReturn = PaperScaleReturn()
    private var previewedID: UUID?
    private var paperReturnPose: PaperPose?
    private var paperReturnImage: NSImage?
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
        // 预览开着时记录发生了删除 / 清空 / 过滤：跟随下一条；记录空了就收窗，
        // 不做孤儿窗口。objectWillChange 是改前通知，转一道主队列再看，读到的一定是改后状态
        sink = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncAfterModelChange() }
    }

    func toggle() {
        isVisible ? close() : open()
    }

    func open() {
        guard model.current != nil else { return }   // 记录空不开窗
        if panel == nil { buildPanel() }
        guard let panel else { return }
        isClosing = false
        panel.ignoresMouseEvents = false
        let resuming = paperFlight.visiblePose != nil && previewedID == model.current?.id
        if !resuming { configureAppearance() }
        openFromPaper(panel, continuing: resuming)
    }

    func close() {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        closeToPaper(panel)
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
        let compactFace = paper?.paperSnapshot?() ?? paperReturnImage
        paperReturnImage = compactFace
        previewedID = model.current?.id
        paperReturnPose = paper?.paperPose
        panel.setFrame(target, display: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        let expandedFace = snapshot(panel.contentView)
        let targetPose = readingPose(frame: panel.frame)
        paperFlight.animate(from: Motion.reduceMotion ? targetPose : origin, to: targetPose,
                            readingImage: expandedFace, compactImage: compactFace, recordID: previewedID, duration: Motion.reduceMotion ? 0.12 : Motion.paperOpenDuration,
                            opening: true, onReady: { [weak self] in
            guard let self else { return }
            self.owner?.setExpandedPaper(self.previewedID)
        }) { [weak self, weak panel] in
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
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1
            self.panel?.ignoresMouseEvents = false
            self.isClosing = false
            self.owner?.setExpandedPaper(nil)
        }
        let origin = readingPose(frame: panel.frame)
        let paper = owner?.previewPaper
        let destination = paper?.paperPose ?? paperReturnPose ?? origin
        let compactFace = paper?.paperSnapshot?() ?? paperReturnImage
        // Capture the current reading viewport once, without resizing it. During
        // a reversal, the existing flight retains its exact face and momentum.
        let readingFace = paperFlight.visiblePose == nil ? snapshot(panel.contentView) : nil
        panel.ignoresMouseEvents = true
        paperFlight.animate(from: origin, to: Motion.reduceMotion ? origin : destination,
            readingImage: readingFace, compactImage: compactFace, recordID: previewedID,
            duration: Motion.reduceMotion ? 0.12 : Motion.paperCloseDuration, opening: false,
            initialVelocity: followVelocity, onReady: { [weak panel] in
                panel?.alphaValue = 0
            }, completion: finish)
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
        hosting?.rootView = PreviewContentView(model: model, mediaLoader: mediaLoader)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.minSize = NSSize(width: 1, height: 1)
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.hasShadow = true
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.cornerRadius = IvoryPaperStyle.radius
        panel.contentView?.layer?.masksToBounds = true
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
        guard isVisible, !isClosing,
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
        // 标题不画出来，但读屏要有名字——VO 念「Untitled」等于没念
        panel.title = L10n.previewTitle
        panel.isFloatingPanel = true
        // 比面板高一级：同层时 orderFront 的先后才不会互相盖
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel
    }

    // MARK: - 落位

    /// Expand from the selected paper's pin, clamped to its display.
    private func targetFrame() -> NSRect {
        let paper = owner?.previewPaper
        let anchor = paper?.frame ?? owner?.previewAnchorFrame
        let screen = anchor.flatMap { a in
            NSScreen.screens.first { $0.frame.intersects(a) }
        } ?? NSScreen.main ?? NSScreen.screens.first
        let base = paperSessionSize ?? Self.paperSize(for: nil)
        guard let screen else { return NSRect(origin: .zero, size: base) }
        let visible = screen.visibleFrame
        let pin = paper?.paperPin ?? anchor.map { NSPoint(x: $0.midX, y: $0.maxY - IvoryPaperStyle.pinInset) }
            ?? NSPoint(x: visible.midX, y: visible.midY)
        return Self.paperFrame(pin: pin, visible: visible,
            size: NSSize(width: base.width * paperMagnification, height: base.height * paperMagnification),
            magnification: paperMagnification)
    }

    private func magnifyPaper(by delta: CGFloat, phase: NSEvent.Phase) -> Bool {
        guard isVisible, !isClosing,
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
            owner?.setExpandedPaper(previewedID)
            paperReturnPose = owner?.previewPaper?.paperPose ?? paperReturnPose
            // Retarget an unfinished unfold from its visible sheet, never reveal
            // the full-size window at the previous card's location.
            needsFlightRetarget = paperFlight.visibleFrame != nil
        }
        guard (panel?.isVisible ?? false), !isClosing else { return }
        guard model.current != nil else {
            close()   // 记录被删空 / 过滤后无结果：预览不孤儿化
            return
        }
        followPaper()
    }
}
