import AppKit
import CoreImage.CIFilterBuiltins

/// "手机同步"面板：显示二维码（地址+配对码）与手动输入信息
@MainActor
final class QRPairPanel {
    static let shared = QRPairPanel()

    private var panel: NSPanel?

    func show() {
        WebSyncServer.shared.start()
        if panel == nil { buildPanel() }
        guard let panel else { return }

        // 刷新内容（IP 可能变化）
        if let contentView = panel.contentView as? NSStackView {
            for v in contentView.subviews {
                if let box = v as? NSBox, let iv = box.contentView?.subviews.compactMap({ $0 as? NSImageView }).first {
                    iv.image = Self.qrImage(WebSyncServer.shared.pairingURL ?? "")
                }
                if let field = v as? NSTextField, field.tag == 100 {
                    field.stringValue = WebSyncServer.shared.pairingURL ?? "（未找到局域网地址，请确认 Wi-Fi）"
                }
                if let field = v as? NSTextField, field.tag == 101 {
                    field.stringValue = "配对码：" + WebSyncServer.shared.pairCode
                }
            }
        }
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

        let qrBox = NSBox()
        qrBox.boxType = .custom
        qrBox.fillColor = .white
        qrBox.cornerRadius = 12
        let qrView = NSImageView()
        qrView.imageScaling = .scaleProportionallyUpOrDown
        qrView.frame = NSRect(x: 0, y: 0, width: 220, height: 220)
        qrBox.contentView = qrView
        qrBox.snpLayout()

        let urlField = NSTextField(labelWithString: "")
        urlField.tag = 100
        urlField.font = .systemFont(ofSize: 11)
        urlField.textColor = .secondaryLabelColor

        let codeField = NSTextField(labelWithString: "")
        codeField.tag = 101
        codeField.font = .systemFont(ofSize: 13, weight: .medium)

        let hint = NSTextField(labelWithString: "同一 Wi-Fi 下扫码即可，连接加密（AES-256-GCM）\n添加到主屏幕可获得 App 般体验")
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(qrBox)
        stack.addArrangedSubview(codeField)
        stack.addArrangedSubview(urlField)
        stack.addArrangedSubview(hint)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 420),
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

extension NSBox {
    /// 简单设置内容尺寸
    func snpLayout() {
        self.contentView?.translatesAutoresizingMaskIntoConstraints = false
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}
