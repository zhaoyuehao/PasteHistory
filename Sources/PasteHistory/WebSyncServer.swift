import Foundation
import CryptoKit
import Network
import AppKit

/// 手机同步服务：局域网内置 HTTP 服务器 + 配对码派生的应用层端到端加密。
///
/// 线程模型（重要）：HTTP 处理全部在专用网络队列执行，**不经过 MainActor**——
/// 否则用户点开菜单栏菜单（menu tracking runloop）或任何主线程弹窗都会让服务假死。
/// 读数据：自建 HistoryDatabase 连接（SQLite WAL 支持多连接并发读）。
/// 写数据：解密后派发到主队列（主线程忙时最多延迟入库，不阻塞响应）。
final class WebSyncServer {
    static let shared = WebSyncServer()

    static let port: UInt16 = 8377

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.verdent.pastehistory.websync")
    private let db: HistoryDatabase   // 读连接（与主库同一文件，WAL 并发读安全）
    private let fm = FileManager.default
    private let iconPNG: Data?        // 主屏图标（CoreGraphics 画一次缓存）
    /// 启动失败原因（端口被占用等），二维码面板要提示给用户
    private(set) var lastError: String?
    /// 401 失败时间戳，用于限速（网络串行队列访问，无需加锁）
    private var authFailures: [TimeInterval] = []

    // MARK: - 配对码与密钥（init 时确定，线程安全只读）

    let pairCode: String
    private let pairToken: String
    private let payloadKey: SymmetricKey

    private init() {
        let saved = UserDefaults.standard.string(forKey: "webSyncPairCode")
        let code = saved ?? String(format: "%06d", Int.random(in: 0..<1_000_000))
        if saved == nil { UserDefaults.standard.set(code, forKey: "webSyncPairCode") }
        pairCode = code

        pairToken = SHA256.hash(data: Data(code.utf8)).map { String(format: "%02x", $0) }.joined()
        let ikm = SymmetricKey(data: Data(code.utf8))
        payloadKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm,
                                            salt: Data("PasteHistory-Pairing-v1".utf8),
                                            info: Data("clip-payload".utf8),
                                            outputByteCount: 32)

        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        db = HistoryDatabase(url: appSupport
            .appendingPathComponent("PasteHistory", isDirectory: true)
            .appendingPathComponent("history.sqlite"))
        iconPNG = Self.makeIconPNG()
    }

    // MARK: - 生命周期（从主线程调用）

    private(set) var isRunning = false

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let bonjourName = Host.current().localizedName ?? "Mac"
        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.service = NWListener.Service(name: bonjourName, type: "_pastehistory._tcp")
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)   // 直接在网络队列上下文，无 MainActor 依赖
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.isRunning = true }
                if case .failed = state { self?.isRunning = false }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = "端口 \(Self.port) 被占用，手机连不上（换端口或退出占用程序后重启本应用）"
            NSLog("[WebSync] 启动失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    /// Mac 睡醒后监听可能失效，重启一次
    func restart() {
        stop()
        lastError = nil
        authFailures.removeAll()
        start()
    }

    /// 本机局域网地址（主线程调用，给二维码面板用）
    @MainActor
    var pairingURL: String? {
        for name in ["en0", "en1"] {
            guard let ip = Self.ifAddress(name) else { continue }
            return "http://\(ip):\(Self.port)/#pair=\(pairCode)"
        }
        return nil
    }

    private static func ifAddress(_ name: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard String(cString: iface.ifa_name) == name else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") { return ip }
        }
        return nil
    }

    // MARK: - 连接与 HTTP 解析（全部在网络队列）

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHTTP(conn, buffer: Data())
    }

    private func receiveHTTP(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let request = Self.parseRequest(buf) {
                self.route(request, conn: conn)
            } else if error == nil, !done, buf.count < 16 << 20 {
                self.receiveHTTP(conn, buffer: buf)
            } else {
                conn.cancel()
            }
        }
    }

    struct HTTPRequest {
        var method: String
        var path: String
        var headers: [String: String]   // 小写 key
        var body: Data
    }

    /// 极简 HTTP/1.1 解析：请求行 + 头 + Content-Length body
    static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).map(String.init).first ?? rawPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<data.index(bodyStart, offsetBy: contentLength))
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - 路由（网络队列执行，禁止任何 MainActor 同步等待）

    private func route(_ req: HTTPRequest, conn: NWConnection) {
        switch req.path {
        case "/", "/index.html":
            respond(conn, status: "200 OK", contentType: "text/html; charset=utf-8",
                    body: Data(WebSyncPage.html.utf8))
            return
        case "/favicon.ico":
            respond(conn, status: "204 No Content", contentType: "image/x-icon", body: Data())
            return
        case "/apple-touch-icon.png", "/icon.png":
            // 免鉴权：浏览器/主屏取图标时不带 token
            if let iconPNG {
                respond(conn, status: "200 OK", contentType: "image/png", body: iconPNG)
            } else {
                respond(conn, status: "404 Not Found", contentType: "application/json",
                        body: Data(#"{"error":"not found"}"#.utf8))
            }
            return
        case "/manifest.json":
            let manifest = """
            {"name":"剪贴板历史","short_name":"剪贴板","start_url":"/","display":"standalone",
             "background_color":"#1c1c1e","theme_color":"#1c1c1e",
             "icons":[{"src":"/apple-touch-icon.png","sizes":"180x180","type":"image/png"}]}
            """
            respond(conn, status: "200 OK", contentType: "application/manifest+json",
                    body: Data(manifest.utf8))
            return
        default:
            break
        }

        // 暴力破解防护：60 秒内连续 10 次 401 就短暂拒绝（6 位码只有 100 万组合）
        let now = Date().timeIntervalSince1970
        authFailures = authFailures.filter { now - $0 < 60 }
        guard authFailures.count < 10 else {
            respond(conn, status: "429 Too Many Requests", contentType: "application/json",
                    body: Data(#"{"error":"too many attempts"}"#.utf8))
            return
        }
        guard req.headers["x-pair-token"] == pairToken else {
            authFailures.append(now)
            respond(conn, status: "401 Unauthorized", contentType: "application/json",
                    body: Data(#"{"error":"unauthorized"}"#.utf8))
            return
        }
        authFailures.removeAll()

        switch (req.method, req.path) {
        case ("GET", "/api/info"):
            let info = """
            {"name":\(Self.jsonString(Host.current().localizedName ?? "Mac")),
             "version":"1.0","encrypted":"aes-256-gcm",
             "count":\(db.totalCount())}
            """
            respond(conn, status: "200 OK", contentType: "application/json",
                    body: Data(info.utf8))

        case ("GET", "/api/clips"):
            let clips = db.list(query: "", limit: 300, offset: 0)
            let items = clips.map { Self.encryptedClipJSON($0, key: payloadKey) }
            let payload = "{\"clips\":[\(items.joined(separator: ","))]}"
            respond(conn, status: "200 OK", contentType: "application/json",
                    body: Data(payload.utf8))

        case ("GET", let p) where p.hasPrefix("/api/image/"):
            let name = String(p.dropFirst("/api/image/".count))
            let imagesDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("PasteHistory/images", isDirectory: true)
            guard name.hasSuffix(".png"), !name.contains(".."),
                  let plain = try? Data(contentsOf: imagesDir.appendingPathComponent(name)),
                  let sealed = try? AES.GCM.seal(plain, using: payloadKey),
                  let combined = sealed.combined else {
                respond(conn, status: "404 Not Found", contentType: "application/json",
                        body: Data(#"{"error":"not found"}"#.utf8))
                return
            }
            respond(conn, status: "200 OK", contentType: "application/octet-stream", body: combined)

        case ("POST", "/api/clips"):
            guard let decoded = try? JSONDecoder().decode(IncomingClip.self, from: req.body),
                  let payloadPlain = decrypt(base64: decoded.payload) else {
                respond(conn, status: "400 Bad Request", contentType: "application/json",
                        body: Data(#"{"error":"bad request"}"#.utf8))
                return
            }
            // 解密成功即响应；入库派发到主队列（主线程忙时延迟执行，不阻塞手机端）
            let jsonText = String(data: payloadPlain, encoding: .utf8)
            DispatchQueue.main.async {
                Self.ingestIncoming(jsonText: jsonText)
            }
            respond(conn, status: "200 OK", contentType: "application/json",
                    body: Data(#"{"ok":true}"#.utf8))

        default:
            respond(conn, status: "404 Not Found", contentType: "application/json",
                    body: Data(#"{"error":"not found"}"#.utf8))
        }
    }

    /// 手机端上传内容入库（主队列执行；避免网络线程碰 MainActor 状态）
    @MainActor
    private static func ingestIncoming(jsonText: String?) {
        guard let jsonText,
              let obj = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
              let text = obj["text"] as? String else { return }
        let kind = ClipKind(rawValue: obj["kind"] as? String ?? "text") ?? .text
        let app = obj["app"] as? String
        switch kind {
        case .text:
            ClipStore.shared.upsert(ClipItem(kind: .text, text: text, sourceApp: app ?? "手机网页"))
        case .image:
            guard let b64 = obj["imageBase64"] as? String,
                  let data = Data(base64Encoded: b64),
                  let img = NSImage(data: data),
                  let saved = ClipStore.shared.saveImage(img) else { return }
            ClipStore.shared.upsert(ClipItem(kind: .image, imageFile: saved.name,
                                             sourceApp: app ?? "手机网页", thumbnailData: saved.thumbnail))
        case .files:
            let paths = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            ClipStore.shared.upsert(ClipItem(kind: .files, filePaths: paths, sourceApp: app ?? "手机网页"))
        }
    }

    // MARK: - 加密 payload

    struct IncomingClip: Codable {
        var payload: String   // base64(nonce+ciphertext+tag)
    }

    /// 单条记录的密文 JSON（元数据明文：id/kind/时间；内容密文）
    static func encryptedClipJSON(_ item: ClipItem, key: SymmetricKey) -> String {
        let plain: [String: String] = {
            var d: [String: String] = [:]
            if let t = item.text { d["text"] = t }
            if let o = item.ocrText { d["ocr"] = o }
            if let p = item.filePaths { d["paths"] = p.joined(separator: "\n") }
            if let s = item.sourceApp { d["app"] = s }
            if let th = item.thumbnailData { d["thumb"] = th.base64EncodedString() }
            return d
        }()
        let payload: String
        if let data = try? JSONSerialization.data(withJSONObject: plain),
           let sealed = try? AES.GCM.seal(data, using: key),
           let combined = sealed.combined {
            payload = combined.base64EncodedString()
        } else {
            payload = ""
        }
        var fields: [String] = []
        fields.append("\"id\":\(jsonString(item.id.uuidString))")
        fields.append("\"kind\":\(jsonString(item.kind.rawValue))")
        fields.append("\"ts\":\(item.createdAt.timeIntervalSince1970)")
        fields.append("\"pinned\":\(item.pinned)")
        if let img = item.imageFile { fields.append("\"img\":\(jsonString(img))") }
        fields.append("\"payload\":\(jsonString(payload))")
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func decrypt(base64: String) -> Data? {
        guard let combined = Data(base64Encoded: base64),
              let sealed = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        return try? AES.GCM.open(sealed, using: payloadKey)
    }

    // MARK: - 响应

    private func respond(_ conn: NWConnection, status: String, contentType: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - 主屏图标（CoreGraphics 直接画，不依赖主线程/字体）

    private static func makeIconPNG(size: Int = 180) -> Data? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(size), u = w / 180
        let rect = CGRect(x: 0, y: 0, width: w, height: w)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 40*u, cornerHeight: 40*u, transform: nil))
        ctx.clip()
        ctx.setFillColor(CGColor(red: 0.04, green: 0.52, blue: 1, alpha: 1))  // #0a84ff
        ctx.fill(rect)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 46*u, y: 38*u, width: 88*u, height: 104*u),
                           cornerWidth: 10*u, cornerHeight: 10*u, transform: nil))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: CGRect(x: 72*u, y: 134*u, width: 36*u, height: 18*u),
                           cornerWidth: 6*u, cornerHeight: 6*u, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(CGColor(red: 0.04, green: 0.52, blue: 1, alpha: 1))
        for i in 0..<3 { ctx.fill(CGRect(x: 58*u, y: (56 + CGFloat(i)*22)*u, width: 64*u, height: 8*u)) }
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? (out as Data) : nil
    }

    private static func jsonString(_ s: String) -> String {
        // 注意：NSJSONSerialization 不允许顶层 String（会抛 ObjC 异常直接崩进程），
        // 必须用 JSONEncoder
        guard let data = try? JSONEncoder().encode(s),
              let str = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return str
    }
}
