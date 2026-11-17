import XCTest
@testable import Shelf

final class SecretScannerTests: XCTestCase {
    // Made-up values in the real formats.
    func testRecognizesKeysAndTokens() {
        XCTAssertEqual(SecretScanner.kind(of: "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaA=="), "Private key")
        XCTAssertEqual(SecretScanner.kind(of: "-----BEGIN PRIVATE KEY-----"), "Private key")
        XCTAssertEqual(SecretScanner.kind(of: "AKIAIOSFODNN7EXAMPLE"), "AWS key")
        XCTAssertEqual(SecretScanner.kind(of: "export TOKEN=ghp_" + String(repeating: "a1B2", count: 9)), "GitHub token")
        XCTAssertEqual(SecretScanner.kind(of: "xoxb-1234567890-abcdefghij"), "Slack token")
        XCTAssertEqual(SecretScanner.kind(of: "AIza" + String(repeating: "x", count: 35)), "Google API key")
        XCTAssertEqual(SecretScanner.kind(of: "sk_live_" + String(repeating: "4", count: 24)), "Stripe key")
        XCTAssertEqual(SecretScanner.kind(of: "sk-ant-api03-" + String(repeating: "Z", count: 30)), "API key")
        XCTAssertEqual(SecretScanner.kind(of: "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"),
                       "Token")
    }

    func testRecognizesPasswordsInConnectionStrings() {
        XCTAssertEqual(SecretScanner.kind(of: "Server=db.example.com;Database=crm;User Id=app;Password=Tr0ub4dor&3;"), "Password")
        XCTAssertEqual(SecretScanner.kind(of: "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=abc123def456=="), "Password")
        XCTAssertEqual(SecretScanner.kind(of: "postgres://admin:s3cret@db.internal:5432/app"), "Password")
    }

    func testRecognizesCardNumbers() {
        XCTAssertEqual(SecretScanner.kind(of: "4111 1111 1111 1111"), "Card number")
        XCTAssertEqual(SecretScanner.kind(of: "5555-5555-5555-4444\n"), "Card number")
        XCTAssertNil(SecretScanner.kind(of: "4111 1111 1111 1112"))        // fails Luhn
        XCTAssertNil(SecretScanner.kind(of: "Order 4111111111111111 shipped"))   // only a bare number counts
    }

    func testLeavesOrdinaryTextAlone() {
        for text in [
            "Send the Q4 invoice to finance before Friday.",
            "https://shop.example/item?id=7&utm_source=mail",
            "ssh://git@github.com/lltrx/shelf-clipboard.git",
            "git@github.com:lltrx/shelf-clipboard.git",
            "Reset your password at https://example.com/reset",
            "let password = readLine()",
            "{\"app\":\"Shelf\",\"version\":\"1.6.0\"}",
            "+1 415 555 0100",
            "AKIA is the prefix of AWS access keys",
        ] {
            XCTAssertNil(SecretScanner.kind(of: text), text)
        }
    }

    func testMasked() {
        XCTAssertEqual(SecretScanner.masked("  AKIAIOSFODNN7EXAMPLE\n"), "••••••••MPLE")
    }
}
