import AppKit

/// Shared by the hanging card, its expanded face and the moving paper.
enum IvoryPaperStyle {
    static let fill = NSColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1)
    static let ink = NSColor(white: 0.16, alpha: 1)
    static let meta = NSColor(white: 0.36, alpha: 1)
    static let edge = NSColor(red: 0.66, green: 0.77, blue: 0.72, alpha: 1)
    static let radius: CGFloat = 4
    static let pinInset: CGFloat = 7
}
