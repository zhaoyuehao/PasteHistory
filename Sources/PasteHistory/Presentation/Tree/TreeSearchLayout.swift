import AppKit

/// Search is a fixed control in the tree window, not a projected scene node.
enum TreeSearchLayout {
    static let size = NSSize(width: 116, height: 92)
    static let bottomInset: CGFloat = 8

    /// Both the native window and SwiftUI decoration use this bottom-left frame.
    static func frame(in treeFrame: NSRect) -> NSRect {
        NSRect(x: treeFrame.midX - size.width / 2, y: treeFrame.minY + bottomInset,
               width: size.width, height: size.height)
    }
}
