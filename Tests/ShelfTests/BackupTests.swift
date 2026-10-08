import XCTest
@testable import Shelf

final class BackupTests: StoreTestCase {
    func testExportOnlyIncludesPinnedItems() throws {
        let pinned = try XCTUnwrap(store.upsert(text("pinned")))
        store.upsert(text("history only"))
        store.setBoard(pinned, store.boards()[0].id)

        let backup = try decode(store.exportPinboards())
        XCTAssertEqual(backup.boards.map(\.name), ["Pinned"])
        XCTAssertEqual(backup.boards[0].items.map(\.text), ["pinned"])
    }

    func testRoundTripIntoAnotherStore() throws {
        let rtf = (type: "public.rtf", data: Data("{\\rtf1 hi}".utf8))
        let board = store.createBoard("Work")
        let t = try XCTUnwrap(store.upsert(text("hi", formats: [rtf])))
        let i = try XCTUnwrap(store.upsert(image([1, 2, 3])))
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        store.setBoard(t, board)
        store.setBoard(i, board)
        store.touch(t, at: created)
        store.setOCR(i, "text in image")

        let (other, _) = try makeStore()
        let result = try other.importPinboards(store.exportPinboards())
        XCTAssertEqual(result.items, 2)

        let items = other.all()
        let boardID = try XCTUnwrap(other.boards().first { $0.name == "Work" }?.id)
        XCTAssertTrue(items.allSatisfy { $0.board == boardID })

        let textItem = try XCTUnwrap(items.first { $0.kind == .text })
        XCTAssertEqual(textItem.text, "hi")
        XCTAssertEqual(textItem.created.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(other.formats(textItem.id).first?.data, rtf.data)

        let imageItem = try XCTUnwrap(items.first { $0.kind == .image })
        XCTAssertEqual(imageItem.ocr, "text in image")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(other.imageURL(imageItem))), Data([1, 2, 3]))
    }

    func testImportingTwiceMergesInsteadOfDuplicating() throws {
        let id = try XCTUnwrap(store.upsert(text("x")))
        store.setBoard(id, store.boards()[0].id)
        let data = try store.exportPinboards()

        let (other, _) = try makeStore()
        try other.importPinboards(data)
        try other.importPinboards(data)
        XCTAssertEqual(other.boards().map(\.name), ["Pinned"])
        XCTAssertEqual(other.all().count, 1)
    }

    func testImportRejectsGarbage() {
        XCTAssertThrowsError(try store.importPinboards(Data("not json".utf8)))
    }

    func testAutoBackupSkipsWhenNothingIsPinned() {
        store.upsert(text("unpinned"))
        store.autoBackup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupsDir.path))
    }

    func testAutoBackupWritesPrivateFileAndKeepsLastSeven() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: store.backupsDir, withIntermediateDirectories: true)
        for day in 1...9 {
            let name = String(format: "pinboards-2020-01-%02d.json", day)
            fm.createFile(atPath: store.backupsDir.appendingPathComponent(name).path, contents: Data("{}".utf8))
        }
        let id = try XCTUnwrap(store.upsert(text("x")))
        store.setBoard(id, store.boards()[0].id)

        store.autoBackup()
        let files = try fm.contentsOfDirectory(atPath: store.backupsDir.path).sorted()
        XCTAssertEqual(files.count, 7)
        XCTAssertFalse(files.contains("pinboards-2020-01-01.json"))   // oldest pruned
        let today = try XCTUnwrap(files.last)
        XCTAssertEqual(try permissions(store.backupsDir.appendingPathComponent(today)), 0o600)
        XCTAssertEqual(try decode(Data(contentsOf: store.backupsDir.appendingPathComponent(today))).boards.count, 1)
    }

    private func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: data)
    }
}
