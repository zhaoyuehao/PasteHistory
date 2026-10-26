import Foundation

enum WebSyncPairing {
    private static let defaultsKey = "webSyncPairCode"

    static func isValid(_ code: String) -> Bool {
        let bytes = Array(code.utf8)
        return bytes.count == 16
            && bytes.allSatisfy { (33...126).contains($0) }
            && bytes.contains { (65...90).contains($0) }
            && bytes.contains { (97...122).contains($0) }
            && bytes.contains { (48...57).contains($0) }
            && bytes.contains { !(48...57).contains($0) && !(65...90).contains($0) && !(97...122).contains($0) }
    }

    static func generate() -> String {
        // SystemRandomNumberGenerator uses the OS CSPRNG. Sample uniformly from
        // all 94 printable, non-space ASCII characters; reject missing classes.
        var random = SystemRandomNumberGenerator()
        while true {
            let bytes = (0..<16).map { _ in UInt8.random(in: 33...126, using: &random) }
            let code = String(decoding: bytes, as: UTF8.self)
            if isValid(code) { return code }
        }
    }

    static func loadOrCreate(defaults: UserDefaults) -> String {
        if let saved = defaults.string(forKey: defaultsKey), isValid(saved) {
            return saved
        }
        // Retire persisted six-digit codes on upgrade, not only on QR refresh.
        let code = generate()
        defaults.set(code, forKey: defaultsKey)
        return code
    }

    static func fragment(for code: String) -> String {
        // Encode delimiters such as &, +, # and % before URLSearchParams reads it.
        "pair=" + code.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }
}
