import AppKit
import CoreImage.CIFilterBuiltins
import QuartzCore
import SwiftUI

/// Phone sync panel: displays the QR code and address.
@MainActor
final class QRPairPanel {
    static let shared = QRPairPanel()

    private var panel: NSPanel?
    private var model = PairModel()
    /// Esc 关闭：红绿灯已藏，键盘退出走这里
    private var escMonitor: Any?

    func show() {
        WebSyncServer.shared.start()
        if panel == nil { buildPanel() }
        guard let panel else { return }

        model.refresh()
        panel.center()
        // 出场与主面板同一套语言：0.22s easeOut 淡入 + scale 0.96→1——三张卡片同一张脸。
        // 以前这里是瞬现，是全项目唯一没有阻尼感的窗口
        panel.alphaValue = 0
        if let view = panel.contentView {
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

    private func buildPanel() {
        let hosting = NSHostingController(rootView: PairPanelView(model: model) {
            Task { @MainActor in
                WebSyncServer.shared.refreshPairingCode()
                Self.shared.model.refresh()
            }
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
        panel.setContentSize(NSSize(width: 320, height: 360))
        panel.center()
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

    func refresh() {
        let url = WebSyncServer.shared.pairingURL ?? ""
        qr = QRPairPanel.qrImage(url)
        address = url.isEmpty ? L10n.noNetworkAddress : url
        warning = WebSyncServer.shared.lastError ?? ""
    }
}

// MARK: - 面板视图

private struct PairPanelView: View {
    @ObservedObject var model: PairModel
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: Icon.action, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                    .help(L10n.refreshQRCode)
                    .accessibilityLabel(L10n.refreshQRCode)
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6))
            )

            HStack(spacing: 5) {
                Text(model.address)
                    .font(.system(size: Scale.meta, design: .monospaced))
                    .foregroundStyle(Palette.meta)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.address, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: Icon.action))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.meta)
                .help(L10n.copyAddress)
                .accessibilityLabel(L10n.copyAddress)
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
        .frame(width: 320, height: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
