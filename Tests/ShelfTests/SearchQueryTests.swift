import XCTest
@testable import Shelf

final class SearchQueryTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_763_380_800)   // 2025-11-17 12:00 UTC

    private func item(_ text: String, app: String?, ago hours: Double, ocr: String? = nil) -> ClipItem {
        ClipItem(id: 1, kind: .text, text: text, image: nil, detail: nil, sourceBundle: nil, sourceName: app,
                 created: now.addingTimeInterval(-hours * 3600), board: nil, formatted: false, ocr: ocr)
    }

    func testPlainWordsAreOnePhrase() {
        let q = SearchQuery("  invoice   total ", now: now, calendar: calendar)
        XCTAssertEqual(q.text, "invoice total")
        XCTAssertNil(q.app)
        XCTAssertTrue(q.matches(item("The invoice total is 42", app: "Mail", ago: 1)))
        XCTAssertFalse(q.matches(item("total invoice", app: "Mail", ago: 1)))
    }

    func testFromApp() {
        let q = SearchQuery("from:slack deploy", now: now, calendar: calendar)
        XCTAssertEqual(q.app, "slack")
        XCTAssertEqual(q.text, "deploy")
        XCTAssertTrue(q.matches(item("deploy at 5", app: "Slack", ago: 1)))
        XCTAssertFalse(q.matches(item("deploy at 5", app: "Mail", ago: 1)))
        XCTAssertFalse(q.matches(item("deploy at 5", app: nil, ago: 1)))
        XCTAssertTrue(SearchQuery("From:google", now: now).matches(item("x", app: "Google Chrome", ago: 1)))
        XCTAssertEqual(SearchQuery("from:", now: now).text, "from:")   // nothing after it: just a word
    }

    func testDates() {
        let today = SearchQuery("@today", now: now, calendar: calendar)
        XCTAssertTrue(today.text.isEmpty)
        XCTAssertTrue(today.matches(item("a", app: nil, ago: 11)))      // 01:00 today
        XCTAssertFalse(today.matches(item("a", app: nil, ago: 13)))     // 23:00 yesterday

        let yesterday = SearchQuery("@Yesterday", now: now, calendar: calendar)
        XCTAssertTrue(yesterday.matches(item("a", app: nil, ago: 13)))
        XCTAssertFalse(yesterday.matches(item("a", app: nil, ago: 11)))
        XCTAssertFalse(yesterday.matches(item("a", app: nil, ago: 37)))

        let week = SearchQuery("@week", now: now, calendar: calendar)
        XCTAssertTrue(week.matches(item("a", app: nil, ago: 6 * 24)))
        XCTAssertFalse(week.matches(item("a", app: nil, ago: 8 * 24)))
        XCTAssertTrue(SearchQuery("@month", now: now).matches(item("a", app: nil, ago: 29 * 24)))
    }

    func testCombinedAndTextInImages() {
        let q = SearchQuery("from:screenshot @today total", now: now, calendar: calendar)
        XCTAssertTrue(q.matches(item("", app: "Screenshot", ago: 2, ocr: "Total due: 42")))
        XCTAssertFalse(q.matches(item("", app: "Screenshot", ago: 30, ocr: "Total due: 42")))
        XCTAssertTrue(SearchQuery("", now: now).isEmpty)
        XCTAssertFalse(SearchQuery("@today", now: now).isEmpty)
    }
}
