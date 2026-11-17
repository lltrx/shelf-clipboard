import Foundation

// Paste As (⌘K): the ways a card can be pasted, and the text changes behind them.
// Foundation only, so it can be unit tested without the UI.

/// One way to paste a card, offered by Paste As (⌘K) and the right-click menu.
enum PasteOption: Hashable {
    case original                 // as it was copied
    case formatted                // text with its fonts, colors and links
    case plain                    // text without formatting
    case markdown                 // formatted text converted to Markdown
    case transform(TextTransform)
    case recognizedText           // the text found in an image
    case paths                    // file paths, one per line
    case names                    // file names, one per line
    case lineByLine               // each line in turn: a paste stack made of the card's lines

    var title: String {
        switch self {
        case .original: return "Paste"
        case .formatted: return "Paste with Formatting"
        case .plain: return "Paste as Plain Text"
        case .markdown: return "Paste as Markdown"
        case .transform(let t): return t.title
        case .recognizedText: return "Paste Text in Image"
        case .paths: return "Paste File Paths"
        case .names: return "Paste File Names"
        case .lineByLine: return "Paste Lines One by One"
        }
    }

    /// The key that picks it while the Paste As menu is open. Unique within each card's menu;
    /// "e" is taken by Copy as File….
    var key: String {
        switch self {
        case .original: return "v"
        case .formatted: return "f"
        case .plain, .recognizedText: return "t"
        case .markdown: return "m"
        case .transform(let t): return t.key
        case .paths: return "p"
        case .names: return "n"
        case .lineByLine: return "s"
        }
    }

    /// The options for a card, in menu sections. Cheap to compute (no parsing), because the
    /// right-click menu is built for every visible card.
    static func sections(kind: ClipKind, formatted: Bool, text: String?, ocr: String?) -> [[PasteOption]] {
        switch kind {
        case .text, .link:
            let first: [PasteOption] = formatted ? [.formatted, .plain, .markdown] : [.original]
            let transforms = TextTransform.allCases.filter { $0.offered(for: text ?? "", isLink: kind == .link) }
            let multiline = kind == .text && (text ?? "").utf8.contains { $0 == 10 || $0 == 13 }
            return [first, transforms.map { .transform($0) }, multiline ? [.lineByLine] : []].filter { !$0.isEmpty }
        case .image:
            return (ocr ?? "").isEmpty ? [[.original]] : [[.original], [.recognizedText]]
        case .file:
            return [[.original], [.paths, .names]]
        }
    }

    static func sections(for item: ClipItem) -> [[PasteOption]] {
        sections(kind: item.kind, formatted: item.formatted, text: item.text, ocr: item.ocr)
    }
}

/// A change made to text just before it is pasted. The card itself is not changed.
enum TextTransform: String, CaseIterable, Hashable {
    case uppercase, lowercase, capitalized, trimWhitespace, joinLines, prettyJSON, removeTracking

    var title: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .capitalized: return "Capitalize Words"
        case .trimWhitespace: return "Trim Whitespace"
        case .joinLines: return "Join Lines"
        case .prettyJSON: return "Format JSON"
        case .removeTracking: return "Remove Tracking from Link"
        }
    }

    var key: String {
        switch self {
        case .uppercase: return "u"
        case .lowercase: return "l"
        case .capitalized: return "c"
        case .trimWhitespace: return "w"
        case .joinLines: return "j"
        case .prettyJSON: return "p"
        case .removeTracking: return "r"
        }
    }

    /// Whether to offer it for this text. Quick checks only; `apply` does the real work.
    func offered(for text: String, isLink: Bool) -> Bool {
        switch self {
        case .removeTracking: return isLink && TextTools.removeTracking(text) != nil
        case _ where isLink: return false   // changing the case of a link breaks it
        case .joinLines: return text.utf8.contains { $0 == 10 || $0 == 13 }
        case .prettyJSON: return TextTools.looksLikeJSON(text)
        default: return true
        }
    }

    /// The changed text, or nil when the change doesn't apply (for example, the text isn't valid JSON).
    func apply(_ text: String) -> String? {
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalized: return text.capitalized
        case .trimWhitespace: return TextTools.trimWhitespace(text)
        case .joinLines: return TextTools.joinLines(text)
        case .prettyJSON: return TextTools.prettyJSON(text)
        case .removeTracking: return TextTools.removeTracking(text)
        }
    }
}

enum TextTools {
    /// Removes trailing spaces, the indentation all lines share, and extra blank lines.
    /// Indentation inside the text (such as nested code) is kept.
    static func trimWhitespace(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        var lines = normalized.components(separatedBy: "\n").map { line -> String in
            var line = line
            while let last = line.last, last == " " || last == "\t" { line.removeLast() }
            return line
        }
        let indents = lines.filter { !$0.isEmpty }.map { String($0.prefix { $0 == " " || $0 == "\t" }) }
        var common = indents.first ?? ""
        for indent in indents.dropFirst() {
            while !indent.hasPrefix(common) { common.removeLast() }
        }
        if !common.isEmpty {
            lines = lines.map { $0.isEmpty ? $0 : String($0.dropFirst(common.count)) }
        }
        var out: [String] = []
        for line in lines {
            if line.isEmpty && (out.last ?? "").isEmpty { continue }   // leading or repeated blank line
            out.append(line)
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// All lines joined into one, separated by single spaces.
    static func joinLines(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Starts with { or [ and ends with } or ]. Quick enough to run while building a menu.
    static func looksLikeJSON(_ text: String) -> Bool {
        func space(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 10 || b == 13 }
        let bytes = text.utf8
        guard let first = bytes.first(where: { !space($0) }), let last = bytes.last(where: { !space($0) }) else { return false }
        return (first == UInt8(ascii: "{") && last == UInt8(ascii: "}")) || (first == UInt8(ascii: "[") && last == UInt8(ascii: "]"))
    }

    /// JSON indented with two spaces. Keys stay in their order and numbers stay as written,
    /// so only the layout changes. Nil if the text isn't valid JSON.
    static func prettyJSON(_ text: String) -> String? {
        guard looksLikeJSON(text), let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var out = ""
        var depth = 0
        var inString = false
        var escaped = false
        var i = 0
        func newline() { out += "\n" + String(repeating: "  ", count: depth) }
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                let close: Character = c == "{" ? "}" : "]"
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == close {       // {} and [] stay on one line
                    out.append(c)
                    out.append(close)
                    i = j
                } else {
                    out.append(c)
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth -= 1
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out += ": "
            case _ where c.isWhitespace:
                break
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }

    /// Query parameters that only exist to track clicks.
    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "mkt_tok", "ref_src",
    ]

    /// Tracking parameters used only by some sites (elsewhere these names may mean something).
    private static let siteTrackingParameters: [String: Set<String>] = [
        "youtube.com": ["si"], "youtu.be": ["si"], "spotify.com": ["si"],
        "x.com": ["s", "t"], "twitter.com": ["s", "t"], "instagram.com": ["igsh"],
    ]

    private static func isTracking(_ name: String, host: String) -> Bool {
        let name = name.lowercased()
        if name.hasPrefix("utm_") || trackingParameters.contains(name) { return true }
        return siteTrackingParameters.contains { site, names in
            (host == site || host.hasSuffix("." + site)) && names.contains(name)
        }
    }

    /// The lines Paste Lines One by One pastes: each line without the spaces around it, blank lines
    /// left out.
    static func stackLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The link without tracking parameters (utm_…, fbclid, gclid…), or nil if it has none.
    static func removeTracking(_ text: String) -> String? {
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: link), let items = parts.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let host = parts.host?.lowercased() ?? ""
        let kept = items.filter { !isTracking($0.name, host: host) }
        guard kept.count < items.count else { return nil }
        parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return parts.string
    }
}

// MARK: - Markdown

/// A stretch of formatted text with one style, as read from an attributed string.
struct StyledRun: Equatable {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: String?

    init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.link = link
    }

    fileprivate func with(_ text: String) -> StyledRun {
        var copy = self
        copy.text = text
        return copy
    }

    fileprivate func sameStyle(_ other: StyledRun) -> Bool {
        bold == other.bold && italic == other.italic && code == other.code && link == other.link
    }
}

/// Converts formatted text to Markdown: bold, italic, links, inline code, code blocks and lists.
/// Each line of rich text is a paragraph, so paragraphs are separated by blank lines.
enum MarkdownWriter {
    static func markdown(_ runs: [StyledRun]) -> String {
        var blocks: [String] = []
        var code: [String]?
        var list: [String]?
        var blanks = 0

        func flush() {
            if let lines = code { blocks.append("```\n" + lines.joined(separator: "\n") + "\n```") }
            if let lines = list { blocks.append(lines.joined(separator: "\n")) }
            code = nil
            list = nil
        }

        for line in lines(runs) {
            let plain = line.map(\.text).joined()
            if plain.allSatisfy(\.isWhitespace) {
                blanks += 1
                continue
            }
            if line.allSatisfy({ $0.code || $0.text.allSatisfy(\.isWhitespace) }) {
                if code != nil {
                    code?.append(contentsOf: Array(repeating: "", count: blanks))   // keep blank lines inside a code block
                    code?.append(plain)
                } else {
                    flush()
                    code = [plain]
                }
            } else if let marker = listMarker(plain) {
                let item = String(repeating: "  ", count: marker.depth) + marker.marker + " "
                    + inline(drop(marker.length, from: line)).trimmingCharacters(in: .whitespaces)
                if list != nil { list?.append(item) } else { flush(); list = [item] }
            } else {
                flush()
                blocks.append(inline(line).trimmingCharacters(in: .whitespaces))
            }
            blanks = 0
        }
        flush()
        return blocks.joined(separator: "\n\n")
    }

    /// The runs split into lines (paragraphs).
    private static func lines(_ runs: [StyledRun]) -> [[StyledRun]] {
        var lines: [[StyledRun]] = [[]]
        for run in runs {
            var current = ""
            for c in run.text {
                if c.isNewline {
                    if !current.isEmpty { lines[lines.count - 1].append(run.with(current)) }
                    lines.append([])
                    current = ""
                } else {
                    current.append(c)
                }
            }
            if !current.isEmpty { lines[lines.count - 1].append(run.with(current)) }
        }
        return lines
    }

    private static func inline(_ line: [StyledRun]) -> String {
        var merged: [StyledRun] = []   // so "**a****b**" becomes "**ab**"
        for run in line {
            if let last = merged.last, last.sameStyle(run) {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        return merged.map(render).joined()
    }

    /// Markers go around the words, not the spaces next to them: "**bold** text", not "**bold **text".
    private static func render(_ run: StyledRun) -> String {
        let chars = Array(run.text)
        guard let first = chars.firstIndex(where: { !$0.isWhitespace }),
              let last = chars.lastIndex(where: { !$0.isWhitespace }) else { return run.text }
        let lead = String(chars[..<first])
        let core = String(chars[first...last])
        let trail = String(chars[(last + 1)...])
        var out: String
        if run.code {
            out = core.contains("`") ? "`` \(core) ``" : "`\(core)`"
        } else {
            let marker = run.bold && run.italic ? "***" : run.bold ? "**" : run.italic ? "*" : ""
            out = marker + core + marker
        }
        if let link = run.link, !link.isEmpty {
            out = core == link ? "<\(link)>" : "[\(out)](\(link))"
        }
        return lead + out + trail
    }

    private struct ListMarker {
        let marker: String   // "-" or "1."
        let depth: Int
        let length: Int      // characters of the line taken by indentation, marker and spacing
    }

    /// Rich text lists come through as "\t•\tItem" or "\t1.\tItem" (one more tab per nesting level).
    private static func listMarker(_ line: String) -> ListMarker? {
        let chars = Array(line)
        var i = 0
        var tabs = 0
        while i < chars.count, chars[i] == "\t" || chars[i] == " " {
            if chars[i] == "\t" { tabs += 1 }
            i += 1
        }
        let start = i
        let marker: String
        if i < chars.count, "•◦▪▫●○■□‣⁃–-*".contains(chars[i]) {
            marker = "-"
            i += 1
        } else {
            while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
            guard i > start, i - start <= 3, i < chars.count, chars[i] == "." || chars[i] == ")" else { return nil }
            marker = String(chars[start..<i]) + "."
            i += 1
        }
        guard i < chars.count, chars[i] == "\t" || chars[i] == " " else { return nil }
        while i < chars.count, chars[i] == "\t" || chars[i] == " " { i += 1 }
        return ListMarker(marker: marker, depth: max(0, tabs - 1), length: i)
    }

    private static func drop(_ count: Int, from line: [StyledRun]) -> [StyledRun] {
        var remaining = count
        var out: [StyledRun] = []
        for run in line {
            let length = run.text.count
            if remaining >= length {
                remaining -= length
                continue
            }
            out.append(run.with(String(run.text.dropFirst(remaining))))
            remaining = 0
        }
        return out
    }
}

// MARK: - Colors

/// Text cards that hold a single CSS hex color ("#1E90FF") show a swatch.
enum ColorText {
    struct RGBA: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    /// "#1E90FF", "#fff", "#1E90FF80" or "#fff8". Returns nil for anything else.
    static func parse(_ text: String) -> RGBA? {
        guard text.utf8.count <= 32 else { return nil }   // cheap: runs for every visible card
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        let hex = Array(t.dropFirst())
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let digits = hex.count <= 4 ? hex.flatMap { [$0, $0] } : hex
        let values = stride(from: 0, to: digits.count, by: 2).compactMap { i in
            Int(String(digits[i...i + 1]), radix: 16).map { Double($0) / 255 }
        }
        guard values.count >= 3 else { return nil }
        return RGBA(red: values[0], green: values[1], blue: values[2], alpha: values.count > 3 ? values[3] : 1)
    }
}
