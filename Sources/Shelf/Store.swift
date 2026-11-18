import Foundation
import SQLite3

enum ClipKind: String {
    case text, link, image, file

    var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return "File"
        }
    }
}

struct ClipItem: Identifiable, Equatable {
    let id: Int64
    var kind: ClipKind
    var text: String?          // text/link content, or newline-separated file paths
    var image: String?         // PNG filename inside the images folder
    var detail: String?        // e.g. "1920 × 1080"
    var sourceBundle: String?
    var sourceName: String?
    var created: Date
    var board: Int64?          // pinboard id; pinned items never expire
    var formatted: Bool        // has rich-text representations stored
    var ocr: String?           // text recognized in images (nil = not processed yet)
    var concealed = false      // placeholder for a password on the clipboard; never stored
    var expires: Date?         // a secret (key, token, password): deleted at this time unless pinned

    var pinned: Bool { board != nil }
    var editable: Bool { !concealed && (kind == .text || kind == .link) }

    /// The card shown while a password manager's copy is on the clipboard. It holds no text: pasting it
    /// sends ⌘V for what's already on the clipboard.
    static func concealedPlaceholder(_ copy: Monitor.ConcealedCopy) -> ClipItem {
        ClipItem(id: -1, kind: .text, text: nil, image: nil, detail: nil, sourceBundle: copy.sourceBundle,
                 sourceName: nil, created: copy.date, board: nil, formatted: false, ocr: nil, concealed: true)
    }
    var filePaths: [String] { kind == .file ? (text ?? "").split(separator: "\n").map(String.init) : [] }
}

/// Everything needed to put a deleted card back (⌘Z).
struct ItemSnapshot {
    var capture: Capture
    var created: Date
    var board: Int64?
    var ocr: String?
    var expires: Date?
}

struct Board: Identifiable, Equatable {
    let id: Int64
    var name: String
}

/// A capture from the pasteboard, before it is stored.
struct Capture {
    var kind: ClipKind
    var text: String?
    var imageData: Data?
    var detail: String?
    var hash: String
    var sourceBundle: String?
    var sourceName: String?
    var formats: [(type: String, data: Data)] = []   // RTF/HTML etc., kept for formatted paste
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Local-only SQLite store in ~/Library/Application Support/Shelf. Nothing here touches the network.
final class Store {
    let dir: URL
    let imagesDir: URL
    private var db: OpaquePointer?

    /// `directory` defaults to ~/Library/Application Support/Shelf; tests pass a temporary folder.
    init(directory: URL? = nil) throws {
        let fm = FileManager.default
        dir = directory ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shelf", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        let owner: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: owner)
        try? fm.setAttributes(owner, ofItemAtPath: dir.path)

        let path = dir.appendingPathComponent("history.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw NSError(domain: "Shelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open \(path)"])
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        exec("PRAGMA journal_mode=WAL;")
        exec("""
            CREATE TABLE IF NOT EXISTS items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT,
                image TEXT,
                detail TEXT,
                hash TEXT NOT NULL UNIQUE,
                source_bundle TEXT,
                source_name TEXT,
                created REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_items_created ON items(created);
            CREATE TABLE IF NOT EXISTS formats(
                item_id INTEGER NOT NULL,
                type TEXT NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY(item_id, type)
            );
            CREATE TABLE IF NOT EXISTS boards(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                position INTEGER NOT NULL DEFAULT 0
            );
            """)
        migrate()
    }

    deinit { sqlite3_close(db) }

    private func migrate() {
        var version = 0
        query("PRAGMA user_version") { s in version = Int(sqlite3_column_int(s, 0)) }
        // v2: pinboards (the single "pinned" flag becomes a "Pinned" board) and OCR text.
        if version < 2 {
            var columns: Set<String> = []
            query("PRAGMA table_info(items)") { s in if let name = col(s, 1) { columns.insert(name) } }
            if !columns.contains("board") { exec("ALTER TABLE items ADD COLUMN board INTEGER;") }
            if !columns.contains("ocr") { exec("ALTER TABLE items ADD COLUMN ocr TEXT;") }
            if boards().isEmpty {
                let id = createBoard("Pinned")
                run("UPDATE items SET board = ? WHERE pinned = 1", [id])
            }
            exec("PRAGMA user_version = 2;")
        }
        // v3: secrets expire.
        if version < 3 {
            var columns: Set<String> = []
            query("PRAGMA table_info(items)") { s in if let name = col(s, 1) { columns.insert(name) } }
            if !columns.contains("expires") { exec("ALTER TABLE items ADD COLUMN expires REAL;") }
            exec("PRAGMA user_version = 3;")
        }
    }

    func imageURL(_ item: ClipItem) -> URL? {
        item.image.map { imagesDir.appendingPathComponent($0) }
    }

    func all() -> [ClipItem] {
        var out: [ClipItem] = []
        query("""
            SELECT id, kind, text, image, detail, source_bundle, source_name, created, board,
                   EXISTS(SELECT 1 FROM formats WHERE item_id = items.id), ocr, expires
            FROM items ORDER BY created DESC
            """) { s in
            out.append(ClipItem(
                id: sqlite3_column_int64(s, 0),
                kind: ClipKind(rawValue: col(s, 1) ?? "") ?? .text,
                text: col(s, 2),
                image: col(s, 3),
                detail: col(s, 4),
                sourceBundle: col(s, 5),
                sourceName: col(s, 6),
                created: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)),
                board: sqlite3_column_type(s, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 8),
                formatted: sqlite3_column_int(s, 9) != 0,
                ocr: col(s, 10),
                expires: sqlite3_column_type(s, 11) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 11))
            ))
        }
        return out
    }

    /// Insert a capture, or move an identical existing item to the front. Returns the item id.
    @discardableResult
    func upsert(_ c: Capture) -> Int64? {
        let now = Date().timeIntervalSince1970
        var existing: Int64?
        query("SELECT id FROM items WHERE hash = ?", [c.hash]) { s in existing = sqlite3_column_int64(s, 0) }
        if let id = existing {
            run("UPDATE items SET created = ?, source_bundle = ?, source_name = ? WHERE id = ?",
                [now, c.sourceBundle, c.sourceName, id])
            // Same text copied again: keep the latest formatting (or none, if copied as plain text).
            run("DELETE FROM formats WHERE item_id = ?", [id])
            saveFormats(id, c.formats)
            return id
        }
        var imageName: String?
        if let data = c.imageData {
            imageName = "\(c.hash).png"
            let url = imagesDir.appendingPathComponent(imageName!)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        }
        run("INSERT INTO items(kind, text, image, detail, hash, source_bundle, source_name, created) VALUES(?,?,?,?,?,?,?,?)",
            [c.kind.rawValue, c.text, imageName, c.detail, c.hash, c.sourceBundle, c.sourceName, now])
        let id = sqlite3_last_insert_rowid(db)
        saveFormats(id, c.formats)
        return id
    }

    func formats(_ id: Int64) -> [(type: String, data: Data)] {
        var out: [(type: String, data: Data)] = []
        query("SELECT type, data FROM formats WHERE item_id = ?", [id]) { s in
            let bytes = sqlite3_column_blob(s, 1)
            let data = bytes.map { Data(bytes: $0, count: Int(sqlite3_column_bytes(s, 1))) } ?? Data()
            out.append((col(s, 0) ?? "", data))
        }
        return out
    }

    private func saveFormats(_ id: Int64, _ formats: [(type: String, data: Data)]) {
        for f in formats {
            run("INSERT OR REPLACE INTO formats(item_id, type, data) VALUES(?,?,?)", [id, f.type, f.data])
        }
    }

    func touch(_ id: Int64, at date: Date = Date()) {
        run("UPDATE items SET created = ? WHERE id = ?", [date.timeIntervalSince1970, id])
    }

    /// Pin to a board, or unpin with nil. A pinned secret is kept: pinning clears its expiry.
    func setBoard(_ id: Int64, _ board: Int64?) {
        run("UPDATE items SET board = ?, pinned = ? WHERE id = ?", [board, board == nil ? 0 : 1, id])
        if board != nil { run("UPDATE items SET expires = NULL WHERE id = ?", [id]) }
    }

    /// Marks a card as a secret that's deleted at `date` (nil: kept like any card).
    func setExpiry(_ id: Int64, _ date: Date?) {
        run("UPDATE items SET expires = ? WHERE id = ? AND pinned = 0", [date?.timeIntervalSince1970, id])
    }

    /// Deletes secrets whose time is up. Returns whether any were deleted.
    @discardableResult
    func deleteExpired(at now: Date = Date()) -> Bool {
        let clause = "pinned = 0 AND expires IS NOT NULL AND expires <= ?"
        var count = 0
        query("SELECT COUNT(*) FROM items WHERE \(clause)", [now.timeIntervalSince1970]) { s in count = Int(sqlite3_column_int(s, 0)) }
        guard count > 0 else { return false }
        deleteWhere(clause, [now.timeIntervalSince1970])
        return true
    }

    /// Forget Last 5 Minutes: deletes unpinned cards copied (or pasted) since `date`.
    func deleteRecent(since date: Date) {
        deleteWhere("pinned = 0 AND created >= ?", [date.timeIntervalSince1970])
    }

    /// A card as it is, to put back after it's deleted. Nil if it's gone, or its image file is.
    func snapshot(_ id: Int64) -> ItemSnapshot? {
        var snap: ItemSnapshot?
        query("SELECT kind, text, image, detail, hash, source_bundle, source_name, created, board, ocr, expires FROM items WHERE id = ?",
              [id]) { s in
            let kind = ClipKind(rawValue: col(s, 0) ?? "") ?? .text
            let image = col(s, 2).flatMap { try? Data(contentsOf: imagesDir.appendingPathComponent($0)) }
            if kind == .image && image == nil { return }
            let capture = Capture(kind: kind, text: col(s, 1), imageData: image, detail: col(s, 3), hash: col(s, 4) ?? "",
                                  sourceBundle: col(s, 5), sourceName: col(s, 6))
            snap = ItemSnapshot(capture: capture, created: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)),
                                board: sqlite3_column_type(s, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 8),
                                ocr: col(s, 9),
                                expires: sqlite3_column_type(s, 10) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 10)))
        }
        snap?.capture.formats = formats(id)
        return snap
    }

    /// Puts a deleted card back as it was: content, formatting, pinboard (if it still exists), date, text
    /// found in it, expiry. Returns its new id.
    @discardableResult
    func restore(_ snap: ItemSnapshot) -> Int64? {
        guard let id = upsert(snap.capture) else { return nil }
        if let board = snap.board, boards().contains(where: { $0.id == board }) { setBoard(id, board) }
        touch(id, at: snap.created)
        if let ocr = snap.ocr { setOCR(id, ocr) }
        if let expires = snap.expires { setExpiry(id, expires) }
        return id
    }

    func delete(_ id: Int64) {
        deleteWhere("id = ?", [id])
    }

    /// Remove unpinned items older than the cutoff. Pinned items are kept forever.
    func prune(olderThan cutoff: Date) {
        deleteWhere("pinned = 0 AND created < ?", [cutoff.timeIntervalSince1970])
    }

    func clearUnpinned() {
        deleteWhere("pinned = 0", [])
    }

    // MARK: - Pinboards

    func boards() -> [Board] {
        var out: [Board] = []
        query("SELECT id, name FROM boards ORDER BY position, id") { s in
            out.append(Board(id: sqlite3_column_int64(s, 0), name: col(s, 1) ?? ""))
        }
        return out
    }

    @discardableResult
    func createBoard(_ name: String) -> Int64 {
        run("INSERT INTO boards(name, position) VALUES(?, (SELECT COALESCE(MAX(position), 0) + 1 FROM boards))", [name])
        return sqlite3_last_insert_rowid(db)
    }

    func renameBoard(_ id: Int64, _ name: String) {
        run("UPDATE boards SET name = ? WHERE id = ?", [name, id])
    }

    /// Deleting a board moves its items back to history, with a fresh 30 days.
    func deleteBoard(_ id: Int64) {
        run("UPDATE items SET board = NULL, pinned = 0, created = ? WHERE board = ?", [Date().timeIntervalSince1970, id])
        run("DELETE FROM boards WHERE id = ?", [id])
    }

    // MARK: - Text recognition

    func imagesNeedingOCR() -> [(id: Int64, url: URL)] {
        var out: [(id: Int64, url: URL)] = []
        query("SELECT id, image FROM items WHERE kind = 'image' AND image IS NOT NULL AND ocr IS NULL") { s in
            if let name = col(s, 1) { out.append((sqlite3_column_int64(s, 0), imagesDir.appendingPathComponent(name))) }
        }
        return out
    }

    func setOCR(_ id: Int64, _ text: String) {
        run("UPDATE items SET ocr = ? WHERE id = ?", [text, id])
    }

    // MARK: - SQLite helpers

    private func deleteWhere(_ clause: String, _ args: [Any?]) {
        var images: [String] = []
        query("SELECT image FROM items WHERE image IS NOT NULL AND \(clause)", args) { s in
            if let name = col(s, 0) { images.append(name) }
        }
        run("DELETE FROM formats WHERE item_id IN (SELECT id FROM items WHERE \(clause))", args)
        run("DELETE FROM items WHERE \(clause)", args)
        for name in images {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
        }
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func run(_ sql: String, _ args: [Any?]) {
        query(sql, args) { _ in }
    }

    private func query(_ sql: String, _ args: [Any?] = [], row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            NSLog("Shelf SQL error: %@", String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(s) }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case let v as String: sqlite3_bind_text(s, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int64: sqlite3_bind_int64(s, idx, v)
            case let v as Int: sqlite3_bind_int64(s, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(s, idx, v)
            case let v as Data:
                _ = v.withUnsafeBytes { sqlite3_bind_blob(s, idx, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT) }
            default: sqlite3_bind_null(s, idx)
            }
        }
        while sqlite3_step(s) == SQLITE_ROW { row(s) }
    }
}

private func col(_ s: OpaquePointer, _ i: Int32) -> String? {
    sqlite3_column_text(s, i).map { String(cString: $0) }
}
