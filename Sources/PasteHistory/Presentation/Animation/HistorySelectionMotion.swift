import SwiftUI

/// Application state describes input timing; only presentation chooses animation.
extension HistoryViewModel {
    var selectionAnimation: Animation {
        selectionFromKeyboard && lastMoveAt.timeIntervalSince(previousMoveAt) < Motion.repeatThreshold
            ? Motion.selectionFast : Motion.selection
    }
}
