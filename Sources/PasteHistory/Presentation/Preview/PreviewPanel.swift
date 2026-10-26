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
///    全文滚动这些状态，系统模板覆盖不了；
/// 2. 动效必须走 Motion 令牌（开窗=面板出现、关窗=面板消失、切换=带方向位移）；
/// 3. nonactivatingPanel 不夺键盘焦点，↑↓ 空格 Esc 仍走面板的键监视器，零改动。
///
/// 生命周期挂在面板下面：面板收起它一定收起，预览窗从不单独存活。
/// 位置每次唤出按面板当前位置重算，不记忆——和面板同一条设计原则。
@MainActor
final class PreviewPanelController: NSObject {
    private let model: HistoryViewModel
    private let presentation: HistoryPresentationState
    private let pairing: PairModel
    private var showingPhone = false
    private var selectionID: UUID? { owner?.previewSelectionID }
    private let mediaLoader: PreviewMediaLoader
    private weak var owner: PanelController?
    private var panel: TreeInteractionPanel?
    private var readingSurface: PaperPreviewSurface?
    private var hosting: NSHostingController<AnyView>?
    private var viewportSession = UUID()
    /// 缩回进行中；卡片窗口始终可见，空格可反向展开。
    private var isClosing = false
    private var sink: Any?
    private let paperFlight = PaperPreviewFlight()
    private var previewedID: UUID?
    private var paperReturnPose: PaperPose?
    private var paperSessionSize: NSSize?
    private var paperMagnification: CGFloat = 1
    private var gestureMagnification: CGFloat = 1

    var window: NSPanel? { panel }
    var isAnimating: Bool { paperFlight.visiblePose != nil }
    var isVisible: Bool { previewedID != nil && (panel?.isVisible ?? false) && !isClosing }

    init(model: HistoryViewModel, owner: PanelController, presentation: HistoryPresentationState, pairing: PairModel) {
        self.presentation = presentation
        self.pairing = pairing
        self.model = model
        self.mediaLoader = PreviewMediaLoader(imagesDirectory: model.store.imagesDirectory)
        self.owner = owner
        super.init()
        // 预览开着时记录发生了删除 / 清空 / 过滤：跟随下一条；记录空了就收窗，
        // 不做孤儿窗口。objectWillChange 是改前通知，转一道主队列再看，读到的一定是改后状态
        sink = Publishers.Merge(model.objectWillChange, presentation.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncAfterModelChange() }
    }

    func toggle() {
        isVisible ? close() : open()
    }

    func open() {
        guard let id = selectionID else { return }
        if isClosing, previewedID == id, let panel {
            isClosing = false
            panel.beginPaperInteraction()
            animateOpen()
            return
        }
        guard let paper = owner?.previewPaper,
              let visual = (paper.contentView as? TreePaperSurface)?.visual else { return }
        let continuing = previewedID != nil
        // A different card starts at its own tree pose with no inherited motion.
        // Reversing this same card's close is handled above without resetting it.
        releasePaper()
        if continuing && showingPhone != presentation.phoneSyncSelected { paperSessionSize = selectedPaperSize }
        if !continuing {
            viewportSession = UUID()
            paperSessionSize = selectedPaperSize
            paperMagnification = 1
            gestureMagnification = 1
        }
        panel = paper
        previewedID = id
        isClosing = false
        paperReturnPose = paper.paperPose
        paper.previewOwnsGeometry = true
        paper.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        paper.title = presentation.phoneSyncSelected ? L10n.phoneSync : L10n.previewTitle
        paper.acceptsKeyboardFocus = false
        paper.enabled = true
        paper.onCollapse = { [weak self] in self?.toggle() }
        paper.onMagnify = { [weak self] delta, phase in self?.magnifyPaper(by: delta, phase: phase) ?? false }
        configureAppearance()
        visual.expansion = 0
        if let pose = paper.paperPose { visual.place(pose, in: paper) }
        if let readingSurface {
            readingSurface.readingSize = paperSessionSize
            visual.attachReading(readingSurface)
        }
        paperFlight.bind(window: paper, sheet: visual)
        owner?.setExpandedPaper(id)
        // The paper still receives pinch/click events while its tree drag handler
        // is disabled. Native reading input opens near the target, before the
        // final settling tail, without taking keyboard focus from search.
        paper.enabled = true
        paper.beginPaperInteraction()
        animateOpen()
    }

    private func animateOpen() {
        guard panel != nil else { return }
        let id = previewedID
        paperFlight.animate(to: readingPose(frame: targetFrame()), opening: true) { [weak self] in
            guard let self, self.previewedID == id, !self.isClosing else { return }
            self.followPaper()
        }
    }

    /// Both ordinary records and the permanent phone card enter the same flight.
    func presentSelection() {
        if isVisible { syncAfterModelChange() }
        else { open() }
    }

    private var selectedPaperSize: NSSize {
        presentation.phoneSyncSelected ? NSSize(width: 340, height: 390) : Self.paperSize(for: model.current)
    }

    private var detailContent: AnyView {
        if presentation.phoneSyncSelected {
            return AnyView(PairPanelView(model: pairing, onRefresh: { [pairing] in pairing.renew() }, paperStyle: true))
        }
        return AnyView(PreviewContentView(model: model, mediaLoader: mediaLoader, viewportSession: viewportSession))
    }

    func close() {
        guard let panel, isVisible, !isClosing else { return }
        isClosing = true
        panel.acceptsKeyboardFocus = false
        if panel.isKeyWindow, owner?.previewAnchorVisible == true { owner?.makePanelKeyAgain() }
        let destination = panel.paperPose ?? paperReturnPose ?? readingPose(frame: panel.frame)
        let id = previewedID
        paperFlight.animate(to: destination, opening: false) { [weak self] in
            guard let self, self.isClosing, self.previewedID == id else { return }
            self.releasePaper()
        }
    }

    /// The collapsed card remains visible in its original window. At expansion
    /// zero removing the transparent reading child cannot exchange the paper.
    private func releasePaper() {
        paperFlight.cancel()
        let released = panel
        if let panel {
            panel.endPaperInteraction()
            panel.onCollapse = nil
            panel.onMagnify = nil
            panel.acceptsKeyboardFocus = false
            if let visual = (panel.contentView as? TreePaperSurface)?.visual {
                visual.acceptsReadingInput = false
                visual.expansion = 0
                if let pose = panel.paperPose ?? paperReturnPose { visual.place(pose, in: panel) }
                visual.detachReading()
            }
            panel.previewOwnsGeometry = false
            panel.level = panel.owner?.level ?? .floating
            panel.title = previewedID == IvoryTreeEntry.phoneSyncID ? L10n.phoneSync : "剪贴纸签"
            panel.enabled = true
        }
        panel = nil
        previewedID = nil
        isClosing = false
        owner?.setExpandedPaper(nil)
        released?.onReleasePreview?()
    }

    private func readingPose(frame: NSRect) -> PaperPose {
        let scale = frame.width / (paperSessionSize?.width ?? frame.width)
        return PaperPose(frame: frame, inset: IvoryPaperStyle.pinInset * scale)
    }

    func closeImmediately() { releasePaper() }

    private func configureAppearance() {
        showingPhone = presentation.phoneSyncSelected
        if showingPhone { pairing.prepare() }
        if let hosting { hosting.rootView = detailContent }
        else {
            let hosting = NSHostingController(rootView: detailContent)
            hosting.safeAreaRegions = []
            self.hosting = hosting
            readingSurface = PaperPreviewSurface(document: hosting.view)
        }
        panel?.appearance = NSAppearance(named: .aqua)
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
        guard let panel, panel.isVisible else { return }
        if isClosing {
            if let pose = panel.paperPose {
                paperFlight.retargetFlight(to: pose, opening: false)
            }
            return
        }
        guard isVisible else { return }
        if previewedID != selectionID { open(); return }
        let pose = readingPose(frame: targetFrame())
        if paperFlight.visibleFrame != nil {
            paperFlight.retargetFlight(to: pose, opening: true)
        } else {
            paperFlight.moveLive(panel, to: pose)
        }
    }

    // MARK: - 落位

    /// Expand from the selected paper's pin, clamped to its display.
    private func targetFrame() -> NSRect {
        let paper = owner?.previewPaper
        let anchor = paper?.paperPose?.frame ?? owner?.previewAnchorFrame
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
        gestureMagnification = min(maximum * 1.5, max(0.5, gestureMagnification * (1 + delta)))
        let bounded = min(maximum, max(1, gestureMagnification))
        // A little elastic travel at the limits, never beyond screen capacity.
        let elastic = min(screenMaximum, bounded + (gestureMagnification - bounded) * 0.12)
        if delta != 0 || phase.contains(.began) { applyPaperMagnification(elastic) }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            AnchorTrace.write("preview-pinch ended scale=\(bounded) width=\(panel.frame.width)")
            gestureMagnification = bounded
            paperMagnification = bounded
            let target = targetFrame()
            if paperFlight.visibleFrame != nil {
                paperFlight.retargetFlight(to: readingPose(frame: target), opening: true)
            } else {
                paperFlight.moveLive(panel, to: readingPose(frame: target))
            }
        }
        return true
    }

    private func applyPaperMagnification(_ scale: CGFloat) {
        guard let panel, isVisible, !isClosing else { return }
        paperMagnification = scale
        let target = targetFrame()
        if paperFlight.visibleFrame != nil {
            paperFlight.retargetFlight(to: readingPose(frame: target), opening: true)
        } else {
            paperFlight.trackLive(panel, pose: readingPose(frame: target))
        }
    }

    private func syncAfterModelChange() {
        guard isVisible else { return }
        guard selectionID != nil else { close(); return }
        if previewedID != selectionID {
            // Reuse the live document, but start motion from the next card's
            // own collapsed pose. Keep the session's reading size and zoom.
            open()
        } else {
            followPaper()
        }
    }
}
