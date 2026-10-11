import XCTest
@testable import Shelf

final class ShelfModelTests: XCTestCase {
    private func item(_ id: Int64, _ text: String, board: Int64? = nil) -> ClipItem {
        ClipItem(id: id, kind: .text, text: text, image: nil, detail: nil, sourceBundle: nil, sourceName: nil,
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
}
