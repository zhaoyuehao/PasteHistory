import AppKit
import SwiftUI

// MARK: - 预览内容

struct PreviewContentView: View {
    @ObservedObject var model: HistoryViewModel
    let mediaLoader: PreviewMediaLoader
    private let viewportSession = UUID()
    private struct ViewportID: Hashable { let record: UUID?; let session: UUID }

    @State private var contentOpacity: Double = 1
    /// 驱动切换动画的内容身份。model 的变化不经过我们的事务，
    /// 切换动画必须由这里的 withAnimation 挂上去
    @State private var displayedID: UUID?
    /// 边界橡皮筋：到达边界时下沉再弹回
    @State private var bounceOffset: CGFloat = 0
    /// 原图（后台降采样解码完）；解码期间先用 DB 缩略图顶着，到了原位替换
    @State private var fullImage: NSImage?
    /// 原图的原始像素尺寸（读文件头，不解码整图）
    @State private var originalPixels: CGSize?
    /// 预览图文件字节数（与像素尺寸一样在后台读，body 里不再做磁盘 I/O）
    @State private var fileBytes: Int?
    /// 当前条目对应的预览图文件：`previewImageURL` 里有 fileExists（磁盘 I/O），
    /// 现在只在切换条目时解析一次
    @State private var imageURL: URL?

    /// 正在展示的条目：按 displayedID 找回，而不是直接读 model.current——
    /// 后者在切换的那一拍已经指向新条目，会跳过过渡直接换内容
    private var displayedItem: ClipItem? {
        guard let displayedID else { return model.current }
        return model.results.first { $0.id == displayedID } ?? model.current
    }

    var body: some View {
        if let item = displayedItem {
            VStack(spacing: 0) {
                paperHeader(item)
                ZStack {
                    content(item)
                        // 切换记录重置阅读视口，整张纸的移动由预览控制器负责。
                        .id(ViewportID(record: displayedID, session: viewportSession))
                        .opacity(contentOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // 撞到顶/底：预览内容被推后回弹
                .offset(y: bounceOffset)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(IvoryPaperStyle.meta))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Rhythm.xxl).padding(.bottom, Rhythm.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .background(Color(IvoryPaperStyle.fill))
            .clipShape(RoundedRectangle(cornerRadius: IvoryPaperStyle.radius))
            .overlay {
                RoundedRectangle(cornerRadius: IvoryPaperStyle.radius)
                    .strokeBorder(Color(IvoryPaperStyle.edge), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .task(id: model.current?.id) {
                await step(to: model.current)
            }
            .onChange(of: model.bounceTick) { _, _ in
                // 弹簧没停稳不叠推；「减少动态效果」
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
        imageURL = mediaLoader.url(for: item)
        if displayedID == nil {
            // 首次呈现：直接就位，不做切换动画
            displayedID = item.id
        } else if displayedID != item.id {
            // 连按压短弹簧，不是关掉——连续移动恰恰最需要阻尼
            // Replace the old view immediately: rapid navigation must not retain several
            // expensive text layouts in an outgoing transition.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedID = item.id
                // The whole paper already travels between branches.
                // A second inner slide would make the contents appear to jerk.
                contentOpacity = Motion.reduceMotion ? 0.6 : 1
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(Motion.selectionFast) {
                contentOpacity = 1
            }
        }
        await loadPreviewImage(item)
    }

    // MARK: - 图片加载

    private func loadPreviewImage(_ item: ClipItem) async {
        fullImage = imageURL.flatMap { mediaLoader.cachedImage(at: $0) }
        originalPixels = nil
        fileBytes = nil
        guard let url = imageURL,
              let asset = await mediaLoader.load(url, maxPixel: Preview.maxImagePixel),
              !Task.isCancelled, displayedID == item.id else { return }
        fullImage = asset.image
        originalPixels = asset.pixels
        fileBytes = asset.bytes
    }

    // MARK: - 头部

    /// 挂孔下保留纸签序号、置顶状态和来源。
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

    private static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text: textContent(item)
        case .image: imageContent(item)
        case .files:
            if item.firstImageFilePath != nil && item.filePaths?.count == 1 { imageContent(item) }
            else { filesContent(item) }
        }
    }

    private func textContent(_ item: ClipItem) -> some View {
        let text = item.text ?? ""
        let isTruncated = text.count > Preview.maxTextLength
        return PreviewTextView(text: String(text.prefix(Preview.maxTextLength)), identity: item.id)
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
        PreviewImageDocument(image: fullImage ?? item.thumbnail,
            details: String(ClipPresentation(item: item).imageDetails.prefix(Preview.maxTextLength)),
            identity: item.id)
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
                Divider()
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

    @ViewBuilder
    private var imageStage: some View {
        if let item = displayedItem {
            PreviewImageDocument(image: fullImage ?? item.thumbnail, details: "",
                                 identity: item.id)
        }
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
    final class Coordinator { var identity: UUID?; var text = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PreviewZoomScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 15)
        view.textColor = IvoryPaperStyle.ink
        view.textContainerInset = NSSize(width: Rhythm.xxl, height: Rhythm.l)
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
        scroll.allowsMagnification = false
        if let view = scroll.documentView as? NSTextView {
            view.font = .systemFont(ofSize: 15)
            view.textColor = IvoryPaperStyle.ink
            view.textContainerInset = NSSize(width: Rhythm.xxl, height: Rhythm.l)
        }
        guard context.coordinator.identity != identity || context.coordinator.text != text,
              let view = scroll.documentView as? NSTextView else { return }
        if context.coordinator.identity != identity { (scroll as? PreviewZoomScrollView)?.resetViewport() }
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
                .frame(width: 34, height: 34)   // Fib 档
        } else {
            Color.clear
                .frame(width: 34, height: 34)
        }
    }

    /// stat 放后台；NSWorkspace.icon 不保证线程安全，留在主线程取
    /// （每个身份只取一次，icon services 自带缓存，代价可忽略）
    private func loadDiskInfo() async {
        let metadata = await FileMetadata.read(path: path)
        guard !Task.isCancelled else { return }
        exists = metadata.exists
        sizeText = metadata.bytes.flatMap { $0 > 0 ? ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) : nil }
        icon = NSWorkspace.shared.icon(forFile: path)
    }
}
