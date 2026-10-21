import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Phone sync panel: displays the QR code, address, and pairing code.
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
            Task { @MainActor in
                WebSyncServer.shared.refreshPairingCode()
                Self.shared.model.refresh()
            }
        })
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.title = L10n.phoneSync
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 320, height: 420))
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
        address = url.isEmpty ? L10n.noNetworkAddress : url
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
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Text(L10n.phoneSync)
                        .font(.system(size: 14, weight: .medium))
                    Text(L10n.phoneSyncSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        .help(L10n.encrypted)
                        .accessibilityLabel(L10n.encrypted)
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                    .help(L10n.refreshQRCode)
                    .accessibilityLabel(L10n.refreshQRCode)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

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
            Text(L10n.pairingCodeHint)
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
                .help(L10n.clearAddress)
                .accessibilityLabel(L10n.clearAddress)
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

            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
