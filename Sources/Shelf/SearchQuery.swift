import Foundation

/// What's typed in the search field. `from:mail` keeps cards copied from an app whose name contains
/// "mail"; `@today`, `@yesterday`, `@week` (the last 7 days) and `@month` (the last 30) keep cards
/// from then. Every other word is searched in the text, links, file names, app names and the text
/// found in images, as one phrase. Foundation only, so it can be unit tested without the UI.
struct SearchQuery: Equatable {
    var text = ""
    var app: String?
    var since: Date?
    var until: Date?

    init(_ query: String, now: Date = Date(), calendar: Calendar = .current) {
        var words: [String] = []
        for word in query.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = word.lowercased()
            if lower.hasPrefix("from:"), word.count > 5 {
                app = String(word.dropFirst(5))
                continue
            }
            let today = calendar.startOfDay(for: now)
            switch lower {
            case "@today":
                since = today
            case "@yesterday":
                since = calendar.date(byAdding: .day, value: -1, to: today)
                until = today
            case "@week":
                since = calendar.date(byAdding: .day, value: -7, to: now)
            case "@month":
                since = calendar.date(byAdding: .day, value: -30, to: now)
            default:
                words.append(word)
            }
        }
        text = words.joined(separator: " ")
    }

    var isEmpty: Bool { text.isEmpty && app == nil && since == nil && until == nil }

    func matches(_ item: ClipItem) -> Bool {
        if let app, !(item.sourceName?.localizedCaseInsensitiveContains(app) ?? false) { return false }
        if let since, item.created < since { return false }
        if let until, item.created >= until { return false }
        guard !text.isEmpty else { return true }
        return (item.text?.localizedCaseInsensitiveContains(text) ?? false) ||
            (item.ocr?.localizedCaseInsensitiveContains(text) ?? false) ||
            (item.sourceName?.localizedCaseInsensitiveContains(text) ?? false) ||
            item.kind.title.localizedCaseInsensitiveContains(text)
    }
}
