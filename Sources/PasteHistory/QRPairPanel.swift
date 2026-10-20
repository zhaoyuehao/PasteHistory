import AppKit
import CoreImage.CIFilterBuiltins

/// "手机同步"面板：显示二维码（地址+配对码）与手动输入信息
@MainActor
final class QRPairPanel {
    static let shared = QRPairPanel()

    private var panel: NSPanel?
    private var qrView: NSImageView?
    private var urlField: NSTextField?
    private var codeField: NSTextField?
    private var warnField: NSTextField?

    func show() {
        WebSyncServer.shared.start()
        if panel == nil { buildPanel() }
        guard let panel else { return }

        // 刷新内容（IP 可能变化）
        let url = WebSyncServer.shared.pairingURL ?? ""
        qrView?.image = Self.qrImage(url)
        urlField?.stringValue = url.isEmpty ? "（未找到局域网地址，请确认 Wi-Fi）" : url
        codeField?.stringValue = "配对码：" + WebSyncServer.shared.pairCode
        warnField?.stringValue = WebSyncServer.shared.lastError ?? ""

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func buildPanel() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "手机扫码连接剪贴板")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        // 二维码：白底圆角卡片，显式约束尺寸（不能关掉 autoresizing 又不补约束，会塌成 0）
        let qrView = NSImageView()
        qrView.imageScaling = .scaleProportionallyUpOrDown
        qrView.wantsLayer = true
        qrView.layer?.backgroundColor = NSColor.white.cgColor
        qrView.layer?.cornerRadius = 12
        qrView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            qrView.widthAnchor.constraint(equalToConstant: 220),
            qrView.heightAnchor.constraint(equalToConstant: 220),
        ])
        self.qrView = qrView

        let urlField = NSTextField(labelWithString: "")
        urlField.font = .systemFont(ofSize: 11)
        urlField.textColor = .secondaryLabelColor
        self.urlField = urlField

        let codeField = NSTextField(labelWithString: "")
        codeField.font = .systemFont(ofSize: 13, weight: .medium)
        self.codeField = codeField

        let hint = NSTextField(labelWithString: "同一 Wi-Fi 下扫码即可，连接加密（AES-256-GCM）\n添加到主屏幕可获得 App 般体验")
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        let warnField = NSTextField(wrappingLabelWithString: "")
        warnField.font = .systemFont(ofSize: 11)
        warnField.textColor = .systemOrange
        warnField.alignment = .center
        warnField.maximumNumberOfLines = 2
        self.warnField = warnField

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(qrView)
        stack.addArrangedSubview(warnField)
        stack.addArrangedSubview(codeField)
        stack.addArrangedSubview(urlField)
        stack.addArrangedSubview(hint)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 430),
                            styleMask: [.titled, .closable],
                            backing: .buffered, defer: false)
        panel.title = "手机同步"
        panel.contentView = stack
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
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
