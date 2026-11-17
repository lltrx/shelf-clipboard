import XCTest
@testable import Shelf

final class SnippetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_380_800)   // 2025-11-17 12:00 UTC
    private let utc = TimeZone(identifier: "UTC")!

    func testFindsPlaceholders() {
        XCTAssertTrue(Snippet.hasPlaceholders("Hi, sent on {{date}}"))
        XCTAssertFalse(Snippet.hasPlaceholders("func f() { return {{x}} }"))   // not one of ours
        XCTAssertFalse(Snippet.hasPlaceholders("plain text"))
    }

    func testExpandsDatesClipboardAndIDs() {
        let out = Snippet.expand("Ref {{isodate}} / {{clipboard}} / {{uuid}} / {{date}}", now: now, clipboard: "INV-0423",
                                 locale: Locale(identifier: "en_US"), timeZone: utc)
        XCTAssertTrue(out.hasPrefix("Ref 2025-11-17 / INV-0423 / "), out)
        XCTAssertTrue(out.hasSuffix(" / Nov 17, 2025"), out)
        let uuid = out.components(separatedBy: " / ")[2]
        XCTAssertNotNil(UUID(uuidString: uuid))
        XCTAssertEqual(uuid, uuid.lowercased())
    }

    func testUnknownPlaceholdersAndEmptyClipboard() {
        XCTAssertEqual(Snippet.expand("{{name}} {{clipboard}}!", now: now, clipboard: nil, timeZone: utc), "{{name}} !")
    }
}
