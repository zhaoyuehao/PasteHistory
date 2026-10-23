import Foundation

/// Composition root connects user notices to a presenter. Clipboard operations
/// do not create windows or depend on a particular UI.
@MainActor
enum UserFeedback {
    static var present: (String, TimeInterval) -> Void = { _, _ in }
    static func show(_ message: String, duration: TimeInterval = 2.2) {
        present(message, duration)
    }
}
