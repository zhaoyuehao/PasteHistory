import AppKit

/// 无焦点的临时提示条（不需要任何系统权限）
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, duration: TimeInterval = 2.2) {
        hideWork?.cancel()

        if panel == nil { buildPanel() }
        guard let panel, let label = panel.contentView?.subviews.compactMap({ $0 as? NSTextField }).first else { return }

        label.stringValue = text
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = label.fittingSize
        let width = min(max(fitting.width + 40, 220), 460)
        let height = max(fitting.height + 24, 44)
        position(panel, size: NSSize(width: width, height: height))
        panel.setContentSize(NSSize(width: width, height: height))
        // 出场也要淡入（规范 6.4）：HUD 瞬现是最后剩下的直接切换。降级到淡入淡出
        // 本身就合规，「减少动态效果」无需特殊处理
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel?.animator().alphaValue = 0
            } completionHandler: {
                panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func buildPanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 44),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        container.layer?.cornerRadius = 10

        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Rhythm.xl),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Rhythm.xl),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Rhythm.l),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Rhythm.l),
        ])

        panel.contentView = container
        self.panel = panel
    }

    private static func position(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24))
    }
}
