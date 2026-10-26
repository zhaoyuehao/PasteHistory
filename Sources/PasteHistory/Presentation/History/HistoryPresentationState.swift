import Combine

/// Ephemeral layout state belongs to the UI, not clipboard history operations.
final class HistoryPresentationState: ObservableObject {
    @Published var treeLayoutEditing = false
    @Published var phoneSyncSelected = false
}
