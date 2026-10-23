/// Tree mode reserves Space for preview, including filtered results.
/// Shift-Space inserts a literal query space; IME composition keeps its own keys.
struct HistoryKeyboardState {
    private(set) var navigating = false
    mutating func navigate() { navigating = true }
    mutating func edit() { navigating = false }
    func spacePreviews(query: String, composing: Bool, tree: Bool) -> Bool {
        !composing && (tree || query.isEmpty)
    }
}
