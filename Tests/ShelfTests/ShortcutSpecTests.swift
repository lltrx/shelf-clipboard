import XCTest
@testable import Shelf

final class ShortcutSpecTests: XCTestCase {
    func testParsesAndShowsTheDefaults() throws {
        let open = try XCTUnwrap(ShortcutSpec("cmd+shift+v"))
        XCTAssertEqual(open.display, "⇧⌘V")
        XCTAssertEqual(open.keyCode, 9)
        XCTAssertEqual(open.spec, "shift+cmd+v")
        XCTAssertEqual(ShortcutSpec(open.spec), open)
        XCTAssertEqual(ShortcutSpec("cmd+option+shift+v")?.display, "⌥⇧⌘V")
        XCTAssertEqual(ShortcutSpec("Control + Alt + Space")?.display, "⌃⌥Space")
    }

    func testNeedsCommandOptionOrControl() {
        XCTAssertNil(ShortcutSpec("shift+v"))            // that's a capital V
        XCTAssertNil(ShortcutSpec("v"))
        XCTAssertNil(ShortcutSpec("cmd+shift"))          // no key
        XCTAssertNil(ShortcutSpec("cmd+v+c"))            // two keys
        XCTAssertNil(ShortcutSpec("cmd+f13"))            // not a key shortcuts can use
        XCTAssertNil(ShortcutSpec(""))
    }

    func testRecordsAKeyPress() {
        let s = ShortcutSpec(keyCode: 40, command: true, option: true, shift: false, control: false)
        XCTAssertEqual(s?.spec, "option+cmd+k")
        XCTAssertEqual(s?.display, "⌥⌘K")
        XCTAssertNil(ShortcutSpec(keyCode: 40, command: false, option: false, shift: true, control: false))
        XCTAssertNil(ShortcutSpec(keyCode: 122, command: true, option: false, shift: false, control: false))   // F1
    }

    func testGlobalShortcutsDefaultsAndTurningOff() {
        XCTAssertEqual(GlobalShortcut.open.spec(stored: nil)?.display, "⇧⌘V")
        XCTAssertEqual(GlobalShortcut.previous.spec(stored: nil)?.display, "⌥⇧⌘V")
        XCTAssertEqual(GlobalShortcut.grabText.spec(stored: nil)?.display, "⇧⌘2")
        XCTAssertNil(GlobalShortcut.grabText.spec(stored: ""))                        // turned off
        XCTAssertEqual(GlobalShortcut.open.spec(stored: "")?.display, "⇧⌘V")          // can't be turned off
        XCTAssertEqual(GlobalShortcut.open.spec(stored: "nonsense")?.display, "⇧⌘V")  // unusable: the default
        XCTAssertEqual(GlobalShortcut.previous.spec(stored: "ctrl+option+p")?.display, "⌃⌥P")
        XCTAssertEqual(Set(GlobalShortcut.allCases.map(\.key)).count, GlobalShortcut.allCases.count)
        let defaults = GlobalShortcut.allCases.compactMap { $0.spec(stored: nil) }
        XCTAssertEqual(Set(defaults.map(\.spec)).count, defaults.count)              // no two the same
    }
}
