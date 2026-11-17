import XCTest
@testable import Shelf

final class StoreTests: StoreTestCase {
    func testFreshStoreIsEmptyWithDefaultPinnedBoard() {
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(store.boards().map(\.name), ["Pinned"])
    }

    func testStorageIsPrivateToTheUser() throws {
        XCTAssertEqual(try permissions(dir), 0o700)
        XCTAssertEqual(try permissions(store.imagesDir), 0o700)
        XCTAssertEqual(try permissions(dir.appendingPathComponent("history.sqlite")), 0o600)
    }

    func testUpsertStoresAndReadsBack() throws {
        let id = try XCTUnwrap(store.upsert(text("hello")))
        let item = try XCTUnwrap(store.all().first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "hello")
        XCTAssertEqual(item.sourceName, "Example")
        XCTAssertFalse(item.pinned)
        XCTAssertFalse(item.formatted)
    }

    func testCopyingSameContentAgainMovesItToTheFrontWithoutDuplicating() throws {
        let a = try XCTUnwrap(store.upsert(text("a")))
        store.touch(a, at: Date(timeIntervalSinceNow: -60))
        let b = try XCTUnwrap(store.upsert(text("b")))
        XCTAssertEqual(store.all().map(\.id), [b, a])

        XCTAssertEqual(store.upsert(text("a")), a)
        XCTAssertEqual(store.all().map(\.id), [a, b])
    }

    func testRecopyReplacesFormatting() throws {
        let rtf = (type: "public.rtf", data: Data("{\\rtf1 hi}".utf8))
        let id = try XCTUnwrap(store.upsert(text("hi", formats: [rtf])))
        XCTAssertEqual(store.formats(id).map(\.type), ["public.rtf"])
        XCTAssertTrue(store.all()[0].formatted)

        store.upsert(text("hi"))   // copied again as plain text
        XCTAssertTrue(store.formats(id).isEmpty)
        XCTAssertFalse(store.all()[0].formatted)
    }

    func testImageFileIsWrittenAndRemovedWithItem() throws {
        let id = try XCTUnwrap(store.upsert(image([1, 2, 3])))
        let url = try XCTUnwrap(store.imageURL(store.all()[0]))
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))

        store.delete(id)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPruneRemovesOldUnpinnedButKeepsPinned() throws {
        let board = store.boards()[0].id
        let old = try XCTUnwrap(store.upsert(text("old")))
        let oldPinned = try XCTUnwrap(store.upsert(text("old pinned")))
        let recent = try XCTUnwrap(store.upsert(text("recent")))
        store.touch(old, at: Date(timeIntervalSinceNow: -40 * 86400))
        store.touch(oldPinned, at: Date(timeIntervalSinceNow: -40 * 86400))
        store.setBoard(oldPinned, board)

        store.prune(olderThan: Date(timeIntervalSinceNow: -30 * 86400))
        XCTAssertEqual(Set(store.all().map(\.id)), [oldPinned, recent])
    }

    func testClearUnpinnedKeepsPinned() throws {
        let pinned = try XCTUnwrap(store.upsert(text("keep")))
        store.upsert(text("drop"))
        store.setBoard(pinned, store.boards()[0].id)

        store.clearUnpinned()
        XCTAssertEqual(store.all().map(\.id), [pinned])
    }

    func testUnpinning() throws {
        let id = try XCTUnwrap(store.upsert(text("x")))
        store.setBoard(id, store.boards()[0].id)
        XCTAssertTrue(store.all()[0].pinned)
        store.setBoard(id, nil)
        XCTAssertFalse(store.all()[0].pinned)
        store.clearUnpinned()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testBoardsCreateRenameAndOrder() {
        let work = store.createBoard("Work")
        store.createBoard("Snippets")
        store.renameBoard(work, "Office")
        XCTAssertEqual(store.boards().map(\.name), ["Pinned", "Office", "Snippets"])
    }

    func testDeletingBoardMovesItsItemsBackToHistory() throws {
        let board = store.createBoard("Temp")
        let id = try XCTUnwrap(store.upsert(text("x")))
        store.setBoard(id, board)
        store.touch(id, at: Date(timeIntervalSinceNow: -40 * 86400))

        store.deleteBoard(board)
        XCTAssertFalse(store.boards().contains { $0.id == board })
        let item = try XCTUnwrap(store.all().first)
        XCTAssertFalse(item.pinned)
        // It gets a fresh 30 days rather than being pruned immediately.
        store.prune(olderThan: Date(timeIntervalSinceNow: -30 * 86400))
        XCTAssertEqual(store.all().map(\.id), [id])
    }

    func testOCRQueue() throws {
        let id = try XCTUnwrap(store.upsert(image([9])))
        store.upsert(text("not an image"))
        XCTAssertEqual(store.imagesNeedingOCR().map(\.id), [id])

        store.setOCR(id, "recognized")
        XCTAssertTrue(store.imagesNeedingOCR().isEmpty)
        XCTAssertEqual(store.all().first { $0.id == id }?.ocr, "recognized")
    }

    func testSecretsAreDeletedWhenTheirTimeIsUp() throws {
        let secret = try XCTUnwrap(store.upsert(text("AKIAIOSFODNN7EXAMPLE")))
        let other = try XCTUnwrap(store.upsert(text("hello")))
        store.setExpiry(secret, Date(timeIntervalSinceNow: 300))
        XCTAssertNotNil(store.all().first { $0.id == secret }?.expires)
        XCTAssertFalse(store.deleteExpired())                               // not yet
        XCTAssertTrue(store.deleteExpired(at: Date(timeIntervalSinceNow: 301)))
        XCTAssertEqual(store.all().map(\.id), [other])
    }

    func testPinningKeepsASecret() throws {
        let secret = try XCTUnwrap(store.upsert(text("AKIAIOSFODNN7EXAMPLE")))
        store.setExpiry(secret, Date(timeIntervalSinceNow: 60))
        store.setBoard(secret, store.boards()[0].id)
        XCTAssertNil(store.all()[0].expires)
        XCTAssertFalse(store.deleteExpired(at: Date(timeIntervalSinceNow: 3600)))
        store.setExpiry(secret, Date(timeIntervalSinceNow: 60))             // pinned cards don't take one
        XCTAssertNil(store.all()[0].expires)
    }

    func testForgetRecentKeepsOlderAndPinned() throws {
        let old = try XCTUnwrap(store.upsert(text("old")))
        store.touch(old, at: Date(timeIntervalSinceNow: -600))
        store.upsert(text("just now"))
        let pinned = try XCTUnwrap(store.upsert(text("pinned just now")))
        store.setBoard(pinned, store.boards()[0].id)
        store.deleteRecent(since: Date(timeIntervalSinceNow: -300))
        XCTAssertEqual(Set(store.all().map(\.id)), [old, pinned])
    }

    func testDeletedCardComesBackAsItWas() throws {
        let rtf = (type: "public.rtf", data: Data("{\\rtf1 hi}".utf8))
        let board = store.createBoard("Work")
        let id = try XCTUnwrap(store.upsert(text("hi", formats: [rtf])))
        store.setBoard(id, board)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        store.touch(id, at: created)
        let snap = try XCTUnwrap(store.snapshot(id))
        store.delete(id)
        XCTAssertTrue(store.all().isEmpty)

        let back = try XCTUnwrap(store.restore(snap))
        let item = try XCTUnwrap(store.all().first)
        XCTAssertEqual(item.id, back)
        XCTAssertEqual(item.text, "hi")
        XCTAssertEqual(item.board, board)
        XCTAssertEqual(item.created.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(store.formats(back).first?.data, rtf.data)
    }

    func testDeletedImageComesBackWithItsFile() throws {
        let id = try XCTUnwrap(store.upsert(image([7, 8, 9])))
        store.setOCR(id, "Total 42")
        let snap = try XCTUnwrap(store.snapshot(id))
        store.delete(id)
        let back = try XCTUnwrap(store.restore(snap))
        let item = try XCTUnwrap(store.all().first { $0.id == back })
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.imageURL(item))), Data([7, 8, 9]))
        XCTAssertEqual(item.ocr, "Total 42")
    }

    func testDataSurvivesReopening() throws {
        let id = try XCTUnwrap(store.upsert(text("persist")))
        store.setBoard(id, store.boards()[0].id)
        store = nil

        let reopened = try Store(directory: dir)
        XCTAssertEqual(reopened.all().map(\.text), ["persist"])
        XCTAssertEqual(reopened.boards().map(\.name), ["Pinned"])   // migration doesn't run twice
        XCTAssertTrue(reopened.all()[0].pinned)
    }
}
