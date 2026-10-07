import Foundation

/// Pinboards as one self-contained JSON file (images and formatting embedded as base64).
struct Backup: Codable {
    var version = 1
    var exported: Date
    var boards: [BoardBackup]

    struct BoardBackup: Codable {
        var name: String
        var items: [ItemBackup]
    }

    struct ItemBackup: Codable {
        var kind: String
        var text: String?
        var detail: String?
        var sourceBundle: String?
        var sourceName: String?
        var created: Date
        var ocr: String?
        var image: Data?
        var formats: [FormatBackup]
    }

    struct FormatBackup: Codable {
        var type: String
        var data: Data
    }
}

extension Store {
    var backupsDir: URL { dir.appendingPathComponent("Backups", isDirectory: true) }

    func exportPinboards() throws -> Data {
        let items = all()
        let boards = boards().map { board in
            Backup.BoardBackup(name: board.name, items: items.filter { $0.board == board.id }.map { item in
                Backup.ItemBackup(
                    kind: item.kind.rawValue, text: item.text, detail: item.detail,
                    sourceBundle: item.sourceBundle, sourceName: item.sourceName, created: item.created, ocr: item.ocr,
                    image: imageURL(item).flatMap { try? Data(contentsOf: $0) },
                    formats: formats(item.id).map { Backup.FormatBackup(type: $0.type, data: $0.data) })
            })
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Backup(exported: Date(), boards: boards))
    }

    /// Merges a backup in: boards are matched by name, items already in history are moved onto the board.
    /// Returns (items, boards) imported.
    @discardableResult
    func importPinboards(_ data: Data) throws -> (items: Int, boards: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        var existing = Dictionary(boards().map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        var count = 0
        for board in backup.boards {
            let boardID = existing[board.name] ?? createBoard(board.name)
            existing[board.name] = boardID
            for item in board.items {
                guard let kind = ClipKind(rawValue: item.kind) else { continue }
                let hash: String
                switch kind {
                case .image:
                    guard let png = item.image else { continue }
                    hash = Monitor.digest("image", png)
                case .file: hash = Monitor.digest("file", Data((item.text ?? "").utf8))
                case .text, .link: hash = Monitor.digest("text", Data((item.text ?? "").utf8))
                }
                let capture = Capture(kind: kind, text: item.text, imageData: item.image, detail: item.detail, hash: hash,
                                      sourceBundle: item.sourceBundle, sourceName: item.sourceName,
                                      formats: item.formats.map { ($0.type, $0.data) })
                guard let id = upsert(capture) else { continue }
                setBoard(id, boardID)
                touch(id, at: item.created)
                if let ocr = item.ocr { setOCR(id, ocr) }
                count += 1
            }
        }
        return (count, backup.boards.count)
    }

    /// Daily copy of the pinboards in Application Support/Shelf/Backups, keeping the last 7.
    func autoBackup() {
        guard all().contains(where: \.pinned) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let day = Date().formatted(.iso8601.year().month().day())
        let file = backupsDir.appendingPathComponent("pinboards-\(day).json")
        guard !fm.fileExists(atPath: file.path), let data = try? exportPinboards() else { return }
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        let old = ((try? fm.contentsOfDirectory(atPath: backupsDir.path)) ?? [])
            .filter { $0.hasPrefix("pinboards-") && $0.hasSuffix(".json") }
            .sorted()
            .dropLast(7)
        for name in old { try? fm.removeItem(at: backupsDir.appendingPathComponent(name)) }
    }
}
