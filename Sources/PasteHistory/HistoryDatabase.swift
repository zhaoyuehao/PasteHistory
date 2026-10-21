import Foundation
import SQLite3

/// SQLITE_TRANSIENT：让 sqlite 在 bind 时自行拷贝数据
private let SQLITE_TRANSIENT_FN = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite 持久化：每条记录落库，UI 只分页读当前页，不再全量驻留内存
final class HistoryDatabase {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.verdent.pastehistory.db", qos: .userInteractive)
    let url: URL

    init(url: URL) {
        self.url = url
        let ok = queue.sync { open(at: url) }
        if !ok {
            // 数据库打不开时降级到临时目录，应用不至于不可用
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("PasteHistory-fallback.sqlite")
            _ = queue.sync { open(at: fallback) }
        }
        queue.sync { migrateIfNeeded() }
        queue.sync { migrateAddPinnedAt() }
        queue.sync { migrateTextHashes() }
    }

    deinit {
        if db != nil { sqlite3_close_v2(db) }
    }

    // MARK: - 打开与建表

    private func open(at url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK, let handle else {
            NSLog("[PasteHistory] 打开数据库失败: \(String(cString: sqlite3_errmsg(handle)))")
            return false
        }
        db = handle
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
        CREATE TABLE IF NOT EXISTS clips (
            id           TEXT PRIMARY KEY,
            kind         TEXT NOT NULL,
            text         TEXT,
            search_text  TEXT,
            content_hash TEXT NOT NULL,
            image_file   TEXT,
            file_paths   TEXT,
            source_app   TEXT,
            created_at   REAL NOT NULL,
            pinned       INTEGER NOT NULL DEFAULT 0,
            thumbnail    BLOB,
            ocr_text     TEXT,
            pinned_at    REAL
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_clips_created ON clips(created_at DESC)")
        exec("CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(content_hash)")
        exec("CREATE INDEX IF NOT EXISTS idx_clips_pinned ON clips(pinned, created_at DESC)")
        return true
    }

    /// 旧版文本指纹未去首尾空白，重算所有 text 行的 content_hash（幂等，每次启动跑一遍）
    /// 注意：本方法已在队列内执行，只能调用无 dispatch 的私有方法
    private func migrateTextHashes() {
        guard let s = Stmt(db, "SELECT id, text FROM clips WHERE kind = 'text'") else { return }
        var rows: [(id: String, text: String)] = []
        while s.step() == SQLITE_ROW {
            rows.append((s.colText(0) ?? "", s.colText(1) ?? ""))
        }
        for row in rows {
            let hash = ClipItem.textContentHash(row.text)
            guard let u = Stmt(db, "UPDATE clips SET content_hash = ?1 WHERE id = ?2 AND content_hash != ?1") else { continue }
            u.text(1, hash)
            u.text(2, row.id)
            u.step()
        }
    }

    private func migrateIfNeeded() {
        // v1 -> v2：从旧 JSON 迁移（注意：本方法已在队列内执行，只能调用无 dispatch 的私有方法）
        let legacy = url.deletingLastPathComponent().appendingPathComponent("history.json")
        guard _totalCount() == 0,
              let data = try? Data(contentsOf: legacy),
              let old = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        for item in old { _ = insert(item) }
        try? FileManager.default.moveItem(at: legacy, to: legacy.appendingPathExtension("migrated"))
    }

    /// 老库补列：pinned_at（置顶时间）。新库建表已带，老库 ALTER 追加到末尾，
    /// 列序与 SELECT * 的下标保持一致
    private func migrateAddPinnedAt() {
        guard let s = Stmt(db, "PRAGMA table_info(clips)") else { return }
        var has = false
        while s.step() == SQLITE_ROW {
            if s.colText(1) == "pinned_at" { has = true }
        }
        if !has { exec("ALTER TABLE clips ADD COLUMN pinned_at REAL") }
    }

    private func exec(_ sql: String) {
        guard db != nil else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("[PasteHistory] SQL 执行失败: \(sql) — \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    // MARK: - 语句小工具

    private final class Stmt {
        let handle: OpaquePointer?
        private let db: OpaquePointer?

        init?(_ db: OpaquePointer?, _ sql: String) {
            guard db != nil else { return nil }
            var h: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &h, nil) == SQLITE_OK, h != nil else {
                NSLog("[PasteHistory] prepare 失败: \(sql) — \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "nil")")
                return nil
            }
            handle = h
            self.db = db
        }

        deinit { sqlite3_finalize(handle) }

        func text(_ idx: Int32, _ v: String?) {
            sqlite3_bind_text(handle, idx, v, -1, SQLITE_TRANSIENT_FN)
        }
        func double(_ idx: Int32, _ v: Double) { sqlite3_bind_double(handle, idx, v) }
        func int(_ idx: Int32, _ v: Int) { sqlite3_bind_int(handle, idx, Int32(v)) }
        func blob(_ idx: Int32, _ v: Data?) {
            if let v {
                v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(handle, idx, buf.baseAddress,
                                      Int32(v.count), SQLITE_TRANSIENT_FN)
                }
            } else {
                sqlite3_bind_null(handle, idx)
            }
        }
        func step() -> Int32 { sqlite3_step(handle) }
        func reset() { sqlite3_reset(handle) }

        func colText(_ idx: Int32) -> String? {
            guard let c = sqlite3_column_text(handle, idx) else { return nil }
            return String(cString: c)
        }
        func colDouble(_ idx: Int32) -> Double { sqlite3_column_double(handle, idx) }
        func colInt(_ idx: Int32) -> Int { Int(sqlite3_column_int64(handle, idx)) }
        func colBlob(_ idx: Int32) -> Data? {
            guard let p = sqlite3_column_blob(handle, idx) else { return nil }
            let n = Int(sqlite3_column_bytes(handle, idx))
            return n > 0 ? Data(bytes: p, count: n) : nil
        }
    }

    // MARK: - 行 <-> ClipItem

    private func rowToItem(_ s: Stmt) -> ClipItem {
        let pathsJSON = s.colText(6)
        let paths = pathsJSON.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) }
        return ClipItem(
            id: UUID(uuidString: s.colText(0) ?? "") ?? UUID(),
            kind: ClipKind(rawValue: s.colText(1) ?? "text") ?? .text,
            text: s.colText(2),
            imageFile: s.colText(5),
            filePaths: paths,
            sourceApp: s.colText(7),
            createdAt: Date(timeIntervalSince1970: s.colDouble(8)),
            pinned: s.colInt(9) != 0,
            pinnedAt: s.colDouble(12) > 0 ? Date(timeIntervalSince1970: s.colDouble(12)) : nil,
            thumbnailData: s.colBlob(10),
            ocrText: s.colText(11)
        )
    }

    private func bindItem(_ s: Stmt, _ item: ClipItem) {
        let pathsJSON: String? = item.filePaths.flatMap {
            String(data: (try? JSONEncoder().encode($0)) ?? Data(), encoding: .utf8)
        }
        s.text(1, item.id.uuidString)
        s.text(2, item.kind.rawValue)
        s.text(3, item.text)
        s.text(4, item.searchText())
        s.text(5, item.contentHash)
        s.text(6, item.imageFile)
        s.text(7, pathsJSON)
        s.text(8, item.sourceApp)
        s.double(9, item.createdAt.timeIntervalSince1970)
        s.int(10, item.pinned ? 1 : 0)
        s.blob(11, item.thumbnailData)
        s.text(12, item.ocrText)
        s.double(13, item.pinnedAt?.timeIntervalSince1970 ?? 0)
    }

    private let insertSQL = """
    INSERT INTO clips (id, kind, text, search_text, content_hash, image_file, file_paths,
                       source_app, created_at, pinned, thumbnail, ocr_text, pinned_at)
    VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)
    """

    // MARK: - 公开操作（全部串行队列内执行）

    /// 新增；同内容已存在则仅更新时间置顶（不换 id），返回是否为新插入
    @discardableResult
    func upsert(_ item: ClipItem) -> Bool {
        queue.sync {
            // 已存在同内容（撞指纹多条时取最新一条）→ 更新时间与应用来源即可
            if let s = Stmt(db, "SELECT id FROM clips WHERE content_hash = ?1 ORDER BY created_at DESC LIMIT 1") {
                s.text(1, item.contentHash)
                if s.step() == SQLITE_ROW, let existing = s.colText(0) {
                    if let u = Stmt(db, "UPDATE clips SET created_at = ?1, source_app = ?2 WHERE id = ?3") {
                        u.double(1, item.createdAt.timeIntervalSince1970)
                        u.text(2, item.sourceApp)
                        u.text(3, existing)
                        u.step()
                    }
                    return false
                }
            }
            return insert(item)
        }
    }

    @discardableResult
    private func insert(_ item: ClipItem) -> Bool {
        guard let s = Stmt(db, insertSQL) else { return false }
        bindItem(s, item)
        let rc = s.step()
        if rc != SQLITE_DONE {
            NSLog("[PasteHistory] insert 失败 rc=\(rc)")
            return false
        }
        return true
    }

    /// 用完整记录覆盖写入（同步导入 / OCR 更新用，保留传入的 id 与时间）
    @discardableResult
    func replace(_ item: ClipItem) -> Bool {
        queue.sync {
            guard let s = Stmt(db, """
                INSERT INTO clips (id, kind, text, search_text, content_hash, image_file, file_paths,
                                   source_app, created_at, pinned, thumbnail, ocr_text, pinned_at)
                VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)
                ON CONFLICT(id) DO UPDATE SET
                    kind=excluded.kind, text=excluded.text, search_text=excluded.search_text,
                    content_hash=excluded.content_hash, image_file=excluded.image_file,
                    file_paths=excluded.file_paths, source_app=excluded.source_app,
                    created_at=excluded.created_at, pinned=excluded.pinned,
                    thumbnail=excluded.thumbnail, ocr_text=excluded.ocr_text,
                    pinned_at=excluded.pinned_at
                """) else { return false }
            bindItem(s, item)
            return s.step() == SQLITE_DONE
        }
    }

    private static func likePattern(_ query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%" + escaped.lowercased() + "%"
    }

    /// 筛选条件对应的 SQL 片段；.all 表示不筛选
    private static func filterClause(_ filter: ClipFilter) -> String? {
        switch filter {
        case .all: return nil
        case .text: return "kind = 'text'"
        case .image: return "kind = 'image'"
        case .files: return "kind = 'files'"
        case .pinned: return "pinned = 1"
        }
    }

    /// 搜索词 + 类型筛选拼出的 WHERE 条件；搜索词永远占第一个占位符
    private static func conditions(query: String, filter: ClipFilter) -> [String] {
        var out: [String] = []
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append("search_text LIKE ?1 ESCAPE '\\'")
        }
        if let f = filterClause(filter) { out.append(f) }
        return out
    }

    /// 分页查询：置顶在前，其余时间倒序；query 命中 search_text（含 OCR 文本）
    func list(query: String, filter: ClipFilter = .all, limit: Int, offset: Int) -> [ClipItem] {
        queue.sync { () -> [ClipItem] in
            var items: [ClipItem] = []
            let conds = Self.conditions(query: query, filter: filter)
            let whereSQL = conds.isEmpty ? "" : " WHERE " + conds.joined(separator: " AND ")
            let sql = "SELECT * FROM clips\(whereSQL) ORDER BY pinned DESC, CASE WHEN pinned = 1 THEN COALESCE(pinned_at, created_at) ELSE created_at END DESC, created_at DESC LIMIT ?\(conds.count + 1) OFFSET ?\(conds.count + 2)"
            guard let s = Stmt(db, sql) else { return items }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { s.text(1, Self.likePattern(q)) }
            s.int(Int32(conds.count + 1), limit)
            s.int(Int32(conds.count + 2), offset)
            while s.step() == SQLITE_ROW {
                items.append(rowToItem(s))
            }
            return items
        }
    }

    func counts(query: String, filter: ClipFilter = .all) -> (matched: Int, total: Int) {
        queue.sync {
            let total: Int
            if let s = Stmt(db, "SELECT COUNT(*) FROM clips"), s.step() == SQLITE_ROW {
                total = s.colInt(0)
            } else { total = 0 }

            let conds = Self.conditions(query: query, filter: filter)
            guard !conds.isEmpty else { return (total, total) }
            let sql = "SELECT COUNT(*) FROM clips WHERE " + conds.joined(separator: " AND ")
            guard let s = Stmt(db, sql) else { return (0, total) }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { s.text(1, Self.likePattern(q)) }
            return s.step() == SQLITE_ROW ? (s.colInt(0), total) : (0, total)
        }
    }

    func get(id: UUID) -> ClipItem? {
        queue.sync {
            guard let s = Stmt(db, "SELECT * FROM clips WHERE id = ?1") else { return nil }
            s.text(1, id.uuidString)
            return s.step() == SQLITE_ROW ? rowToItem(s) : nil
        }
    }

    func delete(id: UUID) {
        queue.sync {
            if let s = Stmt(db, "DELETE FROM clips WHERE id = ?1") {
                s.text(1, id.uuidString)
                s.step()
            }
        }
    }

    /// 置顶时顺手记录置顶时间：置顶区按它倒序（新置顶的排第一）。
    /// 老的置顶记录没有 pinned_at，退回按 created_at 排
    func setPinned(id: UUID, pinned: Bool) {
        queue.sync {
            if pinned {
                guard let s = Stmt(db, "UPDATE clips SET pinned = 1, pinned_at = ?1 WHERE id = ?2") else { return }
                s.double(1, Date().timeIntervalSince1970)
                s.text(2, id.uuidString)
                s.step()
            } else {
                guard let s = Stmt(db, "UPDATE clips SET pinned = 0 WHERE id = ?1") else { return }
                s.text(1, id.uuidString)
                s.step()
            }
        }
    }

    /// OCR 完成：写入识别文本 + 场景标签，重建搜索列
    func updateOCR(id: UUID, ocrText: String?, sceneLabels: [String]) {
        queue.sync {
            guard let s = Stmt(db, """
                UPDATE clips SET ocr_text = ?1,
                    search_text = lower(COALESCE(text,'') || char(10) || COALESCE(?1,'') ||
                        char(10) || COALESCE(source_app,'') || char(10) || COALESCE(file_paths,'') ||
                        char(10) || COALESCE(?3,'') ||
                        CASE WHEN kind = 'image' THEN char(10) || '图片 图像 截图 image photo' ELSE '' END)
                WHERE id = ?2 AND kind = 'image'
                """) else { return }
            s.text(1, ocrText)
            s.text(2, id.uuidString)
            s.text(3, sceneLabels.joined(separator: " "))
            s.step()
        }
    }

    func clearAll() {
        queue.sync { exec("DELETE FROM clips") }
    }

    func totalCount() -> Int {
        queue.sync { _totalCount() }
    }

    /// 仅限已在数据库队列内时调用
    private func _totalCount() -> Int {
        guard let s = Stmt(db, "SELECT COUNT(*) FROM clips"), s.step() == SQLITE_ROW else { return 0 }
        return s.colInt(0)
    }

    /// 供 iCloud 首次全量导出用
    func all() -> [ClipItem] {
        queue.sync {
            var items: [ClipItem] = []
            guard let s = Stmt(db, "SELECT * FROM clips ORDER BY created_at ASC") else { return items }
            while s.step() == SQLITE_ROW {
                items.append(rowToItem(s))
            }
            return items
        }
    }

    /// 调试 / 冒烟用
    func rawSQL(_ sql: String) -> [[String]] {
        queue.sync {
            var rows: [[String]] = []
            guard let s = Stmt(db, sql) else { return rows }
            let cols = sqlite3_column_count(s.handle)
            while s.step() == SQLITE_ROW {
                var row: [String] = []
                for i in 0..<cols {
                    row.append(s.colText(i) ?? "NULL")
                }
                rows.append(row)
            }
            return rows
        }
    }
}
