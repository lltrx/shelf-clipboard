import XCTest
@testable import Shelf

final class MonitorTests: XCTestCase {
    func testDigestIsStableAndKindSpecific() {
        let data = Data("same".utf8)
        XCTAssertEqual(Monitor.digest("text", data), Monitor.digest("text", data))
        XCTAssertNotEqual(Monitor.digest("text", data), Monitor.digest("file", data))
        XCTAssertNotEqual(Monitor.digest("text", data), Monitor.digest("text", Data("other".utf8)))
        XCTAssertEqual(Monitor.digest("text", data).count, 64)   // hex SHA-256
    }

    func testIsLink() {
        XCTAssertTrue(Monitor.isLink("https://example.com"))
        XCTAssertTrue(Monitor.isLink("  http://example.com/path?q=1\n"))
        XCTAssertFalse(Monitor.isLink("example.com"))
        XCTAssertFalse(Monitor.isLink("ftp://example.com"))
        XCTAssertFalse(Monitor.isLink("see https://example.com"))
        XCTAssertFalse(Monitor.isLink("https://"))
        XCTAssertFalse(Monitor.isLink(""))
    }
}
