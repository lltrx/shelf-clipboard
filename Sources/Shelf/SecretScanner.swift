import Foundation

/// Recognizes secrets in copied text: keys and tokens in their well-known formats, private keys,
/// passwords in connection strings and URLs, and card numbers. Shelf keeps those only for a few
/// minutes (Settings → Privacy). Only distinctive formats are matched, so ordinary text isn't flagged.
/// Foundation only, so it can be unit tested without the UI.
enum SecretScanner {
    /// What kind of secret the text is or contains ("AWS key", "Password"…), or nil.
    static func kind(of text: String) -> String? {
        guard !text.isEmpty, text.utf8.count <= 20_000 else { return nil }   // secrets are short copies
        let range = NSRange(text.startIndex..., in: text)
        for (name, regex) in patterns where regex.firstMatch(in: text, range: range) != nil {
            return name
        }
        return isCardNumber(text) ? "Card number" : nil
    }

    private static let patterns: [(String, NSRegularExpression)] = {
        let raw: [(String, String)] = [
            ("Private key", #"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"#),
            ("AWS key", #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
            ("GitHub token", #"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})"#),
            ("Slack token", #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#),
            ("Google API key", #"\bAIza[0-9A-Za-z_\-]{35}"#),
            ("Stripe key", #"\b(?:sk|rk)_live_[0-9A-Za-z]{20,}"#),
            ("API key", #"\bsk-(?:ant|proj)-[A-Za-z0-9_\-]{20,}"#),
            ("Token", #"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#),
            // Connection strings write "Password=…" with no spaces; code ("password = x") isn't matched.
            ("Password", #"(?i)\b(?:password|pwd|accountkey|sharedaccesskey|client_secret)=[^\s;'"]{4,}"#),
            ("Password", #"\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s/:@]+:[^\s/@]+@[^\s/]+"#),
        ]
        return raw.map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }   // fixed patterns, covered by tests
    }()

    /// 13–19 digits (spaces or dashes allowed) that pass the Luhn check, and nothing else.
    static func isCardNumber(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 25, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == " " || $0 == "-") }) else { return false }
        let digits = t.compactMap(\.wholeNumberValue)
        return (13...19).contains(digits.count) && luhn(digits)
    }

    static func luhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (i, digit) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// What a card shows instead of the secret: dots and the last four characters.
    static func masked(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "••••••••" + String(t.suffix(4))
    }
}
