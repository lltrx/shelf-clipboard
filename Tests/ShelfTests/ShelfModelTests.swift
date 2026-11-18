import XCTest
@testable import Shelf

final class ShelfModelTests: XCTestCase {
    private func item(_ id: Int64, _ text: String, board: Int64? = nil, kind: ClipKind = .text) -> ClipItem {
        ClipItem(id: id, kind: kind, text: text, image: nil, detail: nil, sourceBundle: nil, sourceName: nil,
                 created: Date(), board: board, formatted: false, ocr: nil)
    }

    private func model() -> ShelfModel {
        let m = ShelfModel()
        m.items = [item(1, "hello"), item(2, "pinned", board: 7)]
        m.boards = [Board(id: 7, name: "Pinned")]
        m.password = .concealedPlaceholder(.init(change: 1, date: Date(), sourceBundle: "com.apple.Passwords"))
        return m
    }

    func testPasswordCardLeadsHistory() {
        let m = model()
        XCTAssertEqual(m.filtered.map(\.id), [-1, 1, 2])
        XCTAssertTrue(m.filtered[0].concealed)
        XCTAssertNil(m.filtered[0].text)            // the placeholder never holds the password
        XCTAssertEqual(m.selected?.concealed, true) // opening the shelf selects it, so Return pastes it
    }

    func testPasswordCardOnlyInUnfilteredHistory() {
        let m = model()
        m.tab = 7
        XCTAssertFalse(m.filtered.contains(where: \.concealed))
        m.tab = nil
        m.query = "hello"
        XCTAssertEqual(m.filtered.map(\.id), [1])
    }

    func testNoPasswordCardWhenClipboardMovedOn() {
        let m = model()
        m.password = nil
        XCTAssertEqual(m.filtered.map(\.id), [1, 2])
    }

    func testPasswordCardCannotJoinStackOrBeEdited() {
        let m = model()
        let password = m.filtered[0]
        m.toggleStack(password)
        XCTAssertTrue(m.stack.isEmpty)
        XCTAssertFalse(password.editable)
    }

    func testKindFilter() {
        let m = model()
        m.items.append(item(3, "https://example.com", kind: .link))
        m.kindFilter = .link
        XCTAssertEqual(m.filtered.map(\.id), [3])          // and no password card
        m.kindFilter = .text
        XCTAssertEqual(m.filtered.map(\.id), [1, 2])
        m.query = "pin"
        XCTAssertEqual(m.filtered.map(\.id), [2])
    }

    func testCycleKindGoesThroughEveryKindAndBackToAll() {
        let m = model()
        m.selection = 1
        m.cycleKind(1)
        XCTAssertEqual(m.kindFilter, .text)
        XCTAssertEqual(m.selection, 0)                      // a new filter starts at the first card
        m.cycleKind(1); m.cycleKind(1); m.cycleKind(1)
        XCTAssertEqual(m.kindFilter, .file)
        m.cycleKind(1)
        XCTAssertNil(m.kindFilter)
        m.cycleKind(-1)
        XCTAssertEqual(m.kindFilter, .file)
    }

    func testPasteStyleFollowsTheTargetApp() {
        let m = ShelfModel()
        m.appStyles = ["com.microsoft.Excel": true, "com.microsoft.Word": false]
        XCTAssertFalse(m.plainByDefault)                    // no app: the default (formatted)
        m.target = .init(bundle: "com.microsoft.Excel", name: "Excel")
        XCTAssertTrue(m.plainByDefault)
        m.target = .init(bundle: "com.apple.TextEdit", name: "TextEdit")
        XCTAssertFalse(m.plainByDefault)
        m.plainEverywhere = true
        XCTAssertTrue(m.plainByDefault)                     // TextEdit follows the default
        m.target = .init(bundle: "com.microsoft.Word", name: "Word")
        XCTAssertFalse(m.plainByDefault)                    // Word keeps its own setting
    }
}
