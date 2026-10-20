import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// "手机同步"面板：显示二维码（地址+配对码）与手动输入信息
@MainActor
final class QRPairPanel {
    static let shared = QRPairPanel()

    private var panel: NSPanel?
    private var model = PairModel()

    func show() {
        WebSyncServer.shared.start()
        if panel == nil { buildPanel() }
        guard let panel else { return }

        model.refresh()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func buildPanel() {
        let hosting = NSHostingController(rootView: PairPanelView(model: model) {
            Task { @MainActor in Self.shared.model.refresh() }
        })
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.title = "手机同步"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 320, height: 452))
        panel.center()
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
    @Published var pairCode = ""
    @Published var warning = ""

    func refresh() {
        let url = WebSyncServer.shared.pairingURL ?? ""
        qr = QRPairPanel.qrImage(url)
        address = url.isEmpty ? "未找到局域网地址，请确认 Wi-Fi" : url
        pairCode = WebSyncServer.shared.pairCode
        warning = WebSyncServer.shared.lastError ?? ""
    }
}

// MARK: - 面板视图

private struct PairPanelView: View {
    @ObservedObject var model: PairModel
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text("手机同步")
                    .font(.system(size: 14, weight: .medium))
                Text("同一 Wi-Fi 下扫码连接")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
            .padding(.top, 18)
            .padding(.bottom, 14)

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
                            Text("等待网络")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        )
                }
            }
            .frame(width: 176, height: 176)
            .padding(10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6))
            )

            Text(model.pairCode.isEmpty ? "------" : model.pairCode)
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .tracking(2)
                .padding(.top, 16)
            Text("配对码，手机端输入一次即可记住")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                .padding(.top, 3)

            HStack(spacing: 5) {
                Text(model.address)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.address, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("复制地址")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
            .padding(.top, 12)

            if !model.warning.isEmpty {
                Text(model.warning)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                Text("端到端加密 · AES-256-GCM")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
            .padding(.top, 12)
            .padding(.bottom, 14)

            Spacer(minLength: 0)

            Button("刷新二维码", action: onRefresh)
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 14)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
