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
    /// 淡出进行中：窗口还没 orderOut，但逻辑上已经算关了
    private var isClosing = false
    /// 关窗动画的代际号：关到一半又开（连按空格）时，作废在排队的 orderOut
    private var closeGeneration = 0
    private var sink: Any?

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
        guard let item = model.current else { return }   // 列表空不开窗
        if panel == nil { buildPanel() }
        guard let panel else { return }
        closeGeneration += 1
        isClosing = false

        // 出现：从面板的几何长出来，就地把面板放大成预览——视线零移动。
        // （侧边落位会把视线拽到面板旁边，用户明确不要）
        // 「长出来」是幅度最大的动效：frame 插值本身就是那个在动的东西，
        // 内容 scale 就不再叠加了，叠两层会过
        let target = targetFrame(for: item)
        if let anchor = owner?.previewAnchorFrame, anchor.width > 0 {
            panel.setFrame(anchor, display: false)
        } else {
            panel.setFrame(target, display: false)
        }
        panel.alphaValue = 0
        // 不 makeKey：键盘焦点始终留在面板，↑↓ 空格 Esc 全都照旧走面板
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel, panel.isVisible, !isClosing else { return }
        closeGeneration += 1
        let generation = closeGeneration
        isClosing = true
        // 预览窗可能因为点选文字拿到过键盘焦点：关窗前还给面板，
        // 否则面板看着开着、却没有键窗口，按键全部落空
        if panel.isKeyWindow, let owner, owner.previewAnchorVisible {
            owner.makePanelKeyAgain()
        }
        // 消失：缩回面板的几何 + 渐隐——开窗是「长出来」，关窗就是「收回去」，
        // 一来一回是同一趟旅程。普通的缩小消失会读出「弹回」很廉价，
        // 但缩回「我出发的地方」有语义，跟 Finder Quick Look 收回图标同款
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if let anchor = owner?.previewAnchorFrame, anchor.width > 0 {
                panel.animator().setFrame(anchor, display: true)
            }
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.closeGeneration == generation, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.isClosing = false
            }
        }
    }

    // MARK: - 构建

    private func buildPanel() {
        let view = PreviewContentView(model: model)
        let hosting = NSHostingController(rootView: view)
        hosting.safeAreaRegions = []
        let panel = NSPanel(contentViewController: hosting)
        // 与面板同一套窗口语言：透明标题栏、藏红绿灯、可拖动背景——一张卡片，不是一扇窗户
        panel.styleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
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
        panel.delegate = self
        self.panel = panel
    }

    // MARK: - 落位

    /// 目标几何：**以面板为中心就地放大**——盖在面板上方，与面板同心。
    /// 用户的视线就在面板上，侧边落位会把视线拽走（用户明确不要）。
    /// 面板中心拿不到才退当前屏居中。屏幕放不下就收高，不挪中心。
    private func targetFrame(for item: ClipItem) -> NSRect {
        let anchor = owner?.previewAnchorFrame
        let screen = anchor.flatMap { a in
            NSScreen.screens.first { $0.frame.intersects(a) }
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(x: 0, y: 0, width: Preview.width, height: Preview.height)
        }
        let visible = screen.visibleFrame

        // 窗高恒为 640×400（黄金矩形），不随内容形态切换；塞不下收到恰好放得下
        let wanted = Preview.height
        let available = visible.height - Preview.margin * 2
        let height = min(wanted, max(Preview.minHeight, available))
        let width = Preview.width

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
        guard let panel, panel.isVisible, !isClosing else { return }
        guard model.current != nil else {
            close()   // 列表被删空 / 过滤后无结果：预览不孤儿化
            return
        }
        // 窗高恒为黄金矩形（640×400），不随内容形态切换——
        // 条目增删后预览跟随下一条，列表空了收窗，窗体几何稳定
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
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

// MARK: - 预览内容

struct PreviewContentView: View {
    @ObservedObject var model: HistoryViewModel

    /// 切换动画的方向：+1 新内容从下浮入（按 ↓），-1 从上（按 ↑）
    @State private var direction: Int = 1
    /// 驱动切换动画的内容身份。model 的变化不经过我们的事务，
    /// 切换动画必须由这里的 withAnimation 挂上去
    @State private var displayedID: UUID?
    /// 边界橡皮筋：与列表共用同一个 bounceTick，两边同步下沉再弹回
    @State private var bounceOffset: CGFloat = 0
    /// 原图（后台降采样解码完）；解码期间先用 DB 缩略图顶着，到了原位替换
    @State private var fullImage: NSImage?
    /// 原图的原始像素尺寸（读文件头，不解码整图）
    @State private var originalPixels: CGSize?

    /// 正在展示的条目：按 displayedID 找回，而不是直接读 model.current——
    /// 后者在切换的那一拍已经指向新条目，会跳过过渡直接换内容
    private var displayedItem: ClipItem? {
        guard let displayedID else { return model.current }
        return model.results.first { $0.id == displayedID } ?? model.current
    }

    var body: some View {
        if let item = displayedItem {
            VStack(spacing: 0) {
                header(item)
                hairline
                ZStack {
                    content(item)
                        // 身份变化驱动切换：旧内容淡出，新内容从按键方向浮入。
                        // 不用交叉淡化——中间没有任何东西在移动，人眼几乎无感，
                        // 和选中高亮用 matchedGeometryEffect 是同一个理由
                        .id(displayedID)
                        .transition(previewTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // 撞到顶/底：预览内容与面板列表一起被推——像一个整体
                .offset(y: bounceOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .background(Color(NSColor.windowBackgroundColor))
            .task(id: model.current?.id) {
                await step(to: model.current)
            }
            .onChange(of: model.bounceTick) { _, _ in
                // 与 HistoryView 同一套规则：弹簧没停稳不叠推；
                // 先瞬间推出去，再让弹簧拉回来
                guard bounceOffset == 0 else { return }
                bounceOffset = CGFloat(model.bounceDirection) * Motion.bounceDistance
                withAnimation(Motion.bounce) { bounceOffset = 0 }
            }
        }
    }

    /// 条目变化 = 切换动画 + 原图加载，两个动作挂在同一次身份变化上
    private func step(to item: ClipItem?) async {
        guard let item else { return }
        if displayedID == nil {
            // 首次呈现：直接就位，不做切换动画
            displayedID = item.id
        } else if displayedID != item.id {
            direction = Self.moveDirection(from: displayedID, to: item.id, in: model.results)
            // 连按压短弹簧，不是关掉——连续移动恰恰最需要阻尼
            let anim = Date().timeIntervalSince(model.lastMoveAt) < Motion.repeatThreshold
                ? Motion.selectionFast
                : Motion.selection
            withAnimation(anim) { displayedID = item.id }
        }
        await loadPreviewImage(item)
    }

    // MARK: - 图片加载

    private func loadPreviewImage(_ item: ClipItem) async {
        guard let url = previewImageURL(item) else {
            fullImage = nil
            originalPixels = nil
            return
        }
        // 先清掉上一条的原图：不能让旧图在新条目上闪一帧
        fullImage = nil
        originalPixels = nil
        let id = item.id
        // 降采样解码放后台：预览窗就 640 宽，8000px 整图进内存是风扇测试
        let decoded = await Task.detached(priority: .userInitiated) {
            (image: Self.downsampledImage(at: url, maxPixel: Preview.maxImagePixel),
             pixels: Self.pixelSize(at: url))
        }.value
        // 解码期间可能已经切到下一条：别把旧图盖到新内容上
        if displayedID == id {
            fullImage = decoded.image
            originalPixels = decoded.pixels
        }
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

    private var previewTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: CGFloat(direction) * Preview.slideDistance).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: - 头部

    /// 标题栏即元信息：类型图标 + 摘要 + 来源·时间·尺寸。
    /// 这三样正是扫列表时的抓手，大窗里保持在场。切换时头部保持稳定，只有内容在走
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
            if let pixels = originalPixels {
                parts.append(L10n.pixelSize(Int(pixels.width), Int(pixels.height)))
            }
            if let url = previewImageURL(item), let bytes = Self.fileBytes(at: url) {
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

    private static func fileBytes(at url: URL) -> Int? {
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
        return ScrollView {
            // 文字可选中：对齐原生 Quick Look，部分复制不用先粘出去
            Text(String(text.prefix(Preview.maxTextLength)))
                .font(.system(size: Scale.body))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Rhythm.xxl)
        }
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
            if previewImageURL(item) != nil {
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
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 文件形态里首个图片文件的元信息：名称 · 像素尺寸 · 大小
    private func fileImageMeta(_ item: ClipItem) -> String? {
        guard let url = previewImageURL(item) else { return nil }
        var parts: [String] = [url.lastPathComponent]
        if let pixels = originalPixels {
            parts.append(L10n.pixelSize(Int(pixels.width), Int(pixels.height)))
        }
        if let bytes = Self.fileBytes(at: url) {
            parts.append(Self.formatBytes(bytes))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 文件行

/// 预览里的单个文件：图标 + 名称 + 大小/所在目录。
/// 文件已被移动或删除就置灰并说明——比渲染一个空白占位诚实
private struct PreviewFileRow: View {
    let path: String

    @State private var hovered = false

    private var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var body: some View {
        HStack(spacing: Rhythm.xl) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: Scale.body))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Rhythm.m) {
                    if exists {
                        if let size = Self.fileSize(path) {
                            Text(size)
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
                            .fill(Color.primary.opacity(0.06))
                    )
                    .fixedSize()
            }
        }
        .padding(.horizontal, Rhythm.l)
        .padding(.vertical, Rhythm.l)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(hovered ? 0.06 : 0))
        )
        .opacity(exists ? 1 : 0.55)
        .animation(Motion.hover, value: hovered)
        .onHover { hovered = $0 }
    }

    private static func fileSize(_ path: String) -> String? {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
              bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
