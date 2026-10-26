import AppKit
import QuartzCore

/// A surface swap is one AppKit display update, not two independently flushed
/// windows. Keep the old surface until the incoming window has drawn its contents.
@MainActor
enum PaperWindowHandoff {
    static func perform(_ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.setDisableActions(true)
            changes()
        }
        // Flush after both visibility changes, never between the two surfaces.
        CATransaction.flush()
    }

    static func prepare(_ window: NSWindow?) {
        guard let window, window.isVisible, window.alphaValue > 0 else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.invalidateShadow()
    }
}
