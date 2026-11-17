import Foundation

/// Placeholders in pinned text cards, filled in when the card is pasted:
/// `{{date}}` and `{{time}}` (this Mac's format), `{{isodate}}` (2026-11-17), `{{datetime}}`,
/// `{{clipboard}}` (what's on the clipboard at that moment) and `{{uuid}}`.
/// Only pinned cards are expanded, so copied code that happens to contain braces is left alone.
/// Foundation only, so it can be unit tested without the UI.
enum Snippet {
    static let placeholders = ["date", "time", "isodate", "datetime", "clipboard", "uuid"]

    static func hasPlaceholders(_ text: String) -> Bool {
        text.contains("{{") && placeholders.contains { text.contains("{{\($0)}}") }
    }

    static func expand(_ text: String, now: Date = Date(), clipboard: String? = nil,
                       locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        func format(_ date: DateFormatter.Style, _ time: DateFormatter.Style) -> String {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = timeZone
            f.dateStyle = date
            f.timeStyle = time
            return f.string(from: now)
        }
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = timeZone
        iso.dateFormat = "yyyy-MM-dd"
        let values: [String: String] = [
            "date": format(.medium, .none),
            "time": format(.none, .short),
            "isodate": iso.string(from: now),
            "datetime": format(.medium, .short),
            "clipboard": clipboard ?? "",
            "uuid": UUID().uuidString.lowercased(),
        ]
        var out = text
        for name in placeholders {
            if let value = values[name] { out = out.replacingOccurrences(of: "{{\(name)}}", with: value) }
        }
        return out
    }
}
