import AppKit
import CoreImage.CIFilterBuiltins
import QuartzCore
import SwiftUI

/// Phone sync panel: displays the QR code and address.
@MainActor
final class QRPairPanel: NSObject, NSWindowDelegate {
    static let shared = QRPairPanel()

    private var panel: NSPanel?
    private var model = PairModel()
    /// Esc 关闭：红绿灯已藏，键盘退出走这里
    private var escMonitor: Any?

    func show() {
        model.prepare()
        if panel == nil { buildPanel() }
        guard let panel else { return }

        // 高度随 warning 自适应：默认 320（卡区 198 : 320 = 0.619 ≈ φ⁻¹，
        // 卡 : 其余 = 1.618——黄金分割的纵向命中）；有警示时加高到 352 容纳
        panel.setContentSize(NSSize(width: 320, height: model.warning.isEmpty ? 320 : 352))
        panel.center()
        // 出场与主面板同一套语言：0.22s easeOut 淡入 + scale 0.96→1——三张卡片同一张脸。
        // 以前这里是瞬现，是全项目唯一没有阻尼感的窗口。
        // 「减少动态效果」开启时跳过缩放，只保留淡入（规范 5.5）
        panel.alphaValue = 0
        if !Motion.reduceMotion, let view = panel.contentView {
            view.wantsLayer = true
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.96
            scale.toValue = 1.0
            scale.duration = 0.22
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.layer?.add(scale, forKey: "pairPanelAppear")
            view.layer?.transform = CATransform3DIdentity
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate()
        installEscMonitor()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// 收场与主面板同款：0.15s easeIn 只淡出不缩小——缩小消失会读出「弹回」，廉价
    func close() {
        guard let panel, panel.isVisible else { return }
        removeEscMonitor()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    // MARK: - Esc 关闭

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Int(event.keyCode) == 53 else { return event }
            self.close()
            return nil
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    /// 规范 6.5 点击外部可关闭：真去了别的应用才收——一拍后问焦点去向，
    /// 与主面板/预览同一套规矩（点自己的菜单栏不算离开）
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            if NSApp.keyWindow == nil {
                self.close()
            }
        }
    }

    private func buildPanel() {
        let hosting = NSHostingController(rootView: PairPanelView(model: model) {
            Self.shared.model.renew()
        })
        let panel = NSPanel(contentViewController: hosting)
        // 卡片语言对齐主面板/预览：nonactivating + 可拖背景；关闭用系统红绿灯 X
        // （用户拍板：自绘 xmark 多余，系统的更熟悉）。最小化/缩放仍藏。
        panel.styleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
        panel.title = L10n.phoneSync
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 320, height: 320))
        panel.center()
        panel.delegate = self
        // 系统红绿灯关闭绕过 close()：清掉 Esc 监听，避免它吞掉别的窗口的 Esc
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.removeEscMonitor() }
        }
        self.panel = panel
    }

    static func qrImage(_ string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // 放大到清晰尺寸
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - 面板状态

@MainActor
final class PairModel: ObservableObject {
    @Published var qr: NSImage?
    @Published var address = ""
    @Published var warning = ""

    private let readConnection: @MainActor () -> (url: String, warning: String)
    private let startService: @MainActor () -> Void
    private let renewCode: @MainActor () -> Void

    init(readConnection: @escaping @MainActor () -> (url: String, warning: String) = {
        (WebSyncServer.shared.pairingURL ?? "", WebSyncServer.shared.lastError ?? "")
    }, startService: @escaping @MainActor () -> Void = { WebSyncServer.shared.start() },
       renewCode: @escaping @MainActor () -> Void = { WebSyncServer.shared.refreshPairingCode() }) {
        self.readConnection = readConnection
        self.startService = startService
        self.renewCode = renewCode
    }

    func prepare() { startService(); refresh() }
    func renew() { renewCode(); refresh() }

    func refresh() {
        let connection = readConnection()
        let url = connection.url
        qr = QRPairPanel.qrImage(url)
        address = url.isEmpty ? L10n.noNetworkAddress : url
        warning = connection.warning
    }
}

// MARK: - 面板视图

struct PairPanelView: View {
    @ObservedObject var model: PairModel
    var onRefresh: () -> Void
    var paperStyle = false

    var body: some View {
        VStack(spacing: 0) {
            if paperStyle {
                Circle().fill(Color(IvoryPaperStyle.meta).opacity(0.7))
                    .frame(width: 3.4, height: 3.4).padding(.top, 5.3)
            }
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Text(L10n.phoneSync)
                        .font(.system(size: Scale.field, weight: .medium))
                        // 标题让开右上按钮区：ZStack 的 topTrailing 曾把整块标题推到
                        // 右上，尾巴被 lock/refresh 压住——「文字有遮挡」的来源
                        .padding(.horizontal, 56)
                    Text(L10n.phoneSyncSubtitle)
                        .font(.system(size: Scale.meta))
                        .foregroundStyle(Palette.meta)
                }
                .frame(maxWidth: .infinity)   // 真居中：不再跟着 ZStack 的 topTrailing 走

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: Icon.mark))
                        .foregroundStyle(Palette.meta)
                        .help(L10n.encrypted)
                        .accessibilityLabel(L10n.encrypted)
                    PairActionButton(symbol: "arrow.clockwise", label: L10n.refreshQRCode, action: onRefresh)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.top, Rhythm.xl)
            .padding(.horizontal, Rhythm.xxl)
            .padding(.bottom, Rhythm.xl)

            Group {
                if let qr = model.qr {
                    Image(nsImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            Text(L10n.waitingForNetwork)
                                .font(.system(size: Scale.meta))
                                .foregroundStyle(Palette.meta)
                        )
                }
            }
            .frame(width: 176, height: 176)
            // 衬边 11 不是档位数，是 φ 精确点：卡含衬 198:320 = 0.6188 ≈ φ⁻¹
            // ——扫码时视线压在整个卡上，这是全项目唯一「有意 φ」的分割
            .padding(11)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Rhythm.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Rhythm.xl)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6))
            )

            HStack(spacing: 5) {
                Text(model.address)
                    .font(.system(size: Scale.meta, design: .monospaced))
                    .foregroundStyle(Palette.meta)
                    .lineLimit(1)
                    .truncationMode(.middle)
                PairActionButton(symbol: "doc.on.doc", label: L10n.copyAddress) {
                    guard model.qr != nil else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.address, forType: .string)
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, Rhythm.l)
            .padding(.vertical, Rhythm.m)
            .background(
                RoundedRectangle(cornerRadius: Rhythm.l)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
            .padding(.top, Rhythm.xl)

            if !model.warning.isEmpty {
                Text(model.warning)
                    .font(.system(size: Scale.meta))
                    // 系统橙在浅色底上只有 2.2:1，当文字用等于看不见
                    .foregroundStyle(Palette.warning)
                    .multilineTextAlignment(.center)
                .padding(.top, Rhythm.l)
                .padding(.horizontal, Rhythm.xxl)
            }

            Spacer(minLength: 0)
        }
        // 高度 320：卡区 198 : 320 ≈ φ⁻¹（黄金分割纵向命中）；warning 出现时 352
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperStyle ? Color.clear : Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: paperStyle ? IvoryPaperStyle.radius : 0))

    }
}

/// Native controls let the shared paper click recognizer distinguish an action
/// from clicking the paper to collapse it.
private struct PairActionButton: NSViewRepresentable {
    let symbol: String
    let label: String
    var action: () -> Void
    func makeNSView(context: Context) -> ActionButton { ActionButton() }
    func updateNSView(_ button: ActionButton, context: Context) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.invoke = action
    }
    final class ActionButton: NSButton {
        var invoke: (() -> Void)?
        init() {
            super.init(frame: .zero)
            isBordered = false
            imagePosition = .imageOnly
            target = self
            action = #selector(performAction)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func performAction() { invoke?() }
    }
}
