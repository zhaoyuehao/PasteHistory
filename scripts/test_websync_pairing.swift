import Foundation
import CryptoKit

@main
struct PairingChecks {
    static func main() throws {
        let suite = "PasteHistory.PairingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WebSyncPairing.loadOrCreate(defaults: defaults)
        precondition(WebSyncPairing.isValid(first))
        precondition(WebSyncPairing.loadOrCreate(defaults: defaults) == first)
        for invalid in ["000123", "123456", "", "abcdefghijklmnop", "Abcdefghijklmno1", "Abcdefghijklm1! "] {
            defaults.set(invalid, forKey: "webSyncPairCode")
            let migrated = WebSyncPairing.loadOrCreate(defaults: defaults)
            precondition(WebSyncPairing.isValid(migrated))
            precondition(migrated != invalid)
            precondition(WebSyncPairing.loadOrCreate(defaults: defaults) == migrated)
        }

        let samples = (0..<1_000).map { _ in WebSyncPairing.generate() }
        precondition(samples.allSatisfy(WebSyncPairing.isValid))
        precondition(Set(samples).count == samples.count)

        // Exercise every printable symbol, including URL delimiters and quotes.
        let symbols = (UInt8(33)...126).filter {
            !(48...57).contains($0) && !(65...90).contains($0) && !(97...122).contains($0)
        }
        let codes = symbols.map { "Abcdefghijklm12" + String(UnicodeScalar($0)) } + Array(samples.prefix(20))
        let fixtures = try codes.map { code -> [String: String] in
            precondition(WebSyncPairing.isValid(code))
            let url = "http://192.0.2.1:8377/#" + WebSyncPairing.fragment(for: code)
            precondition(URL(string: url) != nil)
            let bytes = Data(code.utf8)
            let token = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes),
                                           salt: Data("PasteHistory-Pairing-v1".utf8),
                                           info: Data("clip-payload".utf8), outputByteCount: 32)
            let plain = "Pairing fixture: 中文 & + # %"
            let sealed = try AES.GCM.seal(Data(plain.utf8), using: key)
            return ["code": code, "url": url, "token": token,
                    "key": key.withUnsafeBytes { Data($0).base64EncodedString() },
                    "plain": plain, "payload": sealed.combined!.base64EncodedString()]
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(fixtures))
    }
}
