/// Search keeps normal spaces until the user navigates records. Once navigating,
/// Space previews the selected result; typing resumes query editing.
struct HistoryKeyboardState {
    private(set) var navigating = false
    mutating func navigate() { navigating = true }
    mutating func edit() { navigating = false }
    func spacePreviews(query: String, composing: Bool, tree: Bool) -> Bool {
        !composing && (query.isEmpty || (tree && navigating))
    }
}
