import XCTest
@testable import Shelf

final class PasteOptionsTests: XCTestCase {
    // MARK: Options per card

    func testFormattedTextOffersFormattingChoicesAndTransforms() {
        let sections = PasteOption.sections(kind: .text, formatted: true, text: "Hello world", ocr: nil)
        XCTAssertEqual(sections.first, [.formatted, .plain, .markdown])
        let transforms = sections.dropFirst().flatMap { $0 }
        XCTAssertTrue(transforms.contains(.transform(.uppercase)))
        XCTAssertTrue(transforms.contains(.transform(.trimWhitespace)))
        XCTAssertFalse(transforms.contains(.transform(.joinLines)))      // one line already
        XCTAssertFalse(transforms.contains(.transform(.prettyJSON)))     // not JSON
        XCTAssertFalse(transforms.contains(.transform(.removeTracking))) // not a link
    }

    func testPlainTextHasOnePasteOption() {
        let sections = PasteOption.sections(kind: .text, formatted: false, text: "a\nb", ocr: nil)
        XCTAssertEqual(sections.first, [.original])
        XCTAssertTrue(sections.flatMap { $0 }.contains(.transform(.joinLines)))
    }

    func testSeveralLinesCanBePastedOneByOne() {
        let sections = PasteOption.sections(kind: .text, formatted: false, text: "a\nb", ocr: nil)
        XCTAssertEqual(sections.last, [.lineByLine])
        XCTAssertFalse(PasteOption.sections(kind: .text, formatted: false, text: "one line", ocr: nil)
            .flatMap { $0 }.contains(.lineByLine))
        XCTAssertEqual(TextTools.stackLines("  Alice \n\nBob\r\n\t\n carol@example.com  "),
                       ["Alice", "Bob", "carol@example.com"])
        XCTAssertEqual(TextTools.stackLines("\n \n"), [])
    }

    func testJSONIsOfferedFormatting() {
        let sections = PasteOption.sections(kind: .text, formatted: false, text: " {\"a\": 1} ", ocr: nil)
        XCTAssertTrue(sections.flatMap { $0 }.contains(.transform(.prettyJSON)))
    }

    func testLinksOnlyOfferTrackingRemovalWhenThereIsTracking() {
        let tracked = PasteOption.sections(kind: .link, formatted: false, text: "https://a.com/?utm_source=x", ocr: nil)
        XCTAssertEqual(tracked, [[.original], [.transform(.removeTracking)]])
        let clean = PasteOption.sections(kind: .link, formatted: false, text: "https://a.com/?q=1", ocr: nil)
        XCTAssertEqual(clean, [[.original]])
    }

    func testImagesOfferRecognizedTextOnlyWhenThereIsSome() {
        XCTAssertEqual(PasteOption.sections(kind: .image, formatted: false, text: nil, ocr: nil), [[.original]])
        XCTAssertEqual(PasteOption.sections(kind: .image, formatted: false, text: nil, ocr: ""), [[.original]])
        XCTAssertEqual(PasteOption.sections(kind: .image, formatted: false, text: nil, ocr: "Total 42"),
                       [[.original], [.recognizedText]])
    }

    func testFilesOfferPathsAndNames() {
        XCTAssertEqual(PasteOption.sections(kind: .file, formatted: false, text: "/a/b.txt", ocr: nil),
                       [[.original], [.paths, .names]])
    }

    func testMenuKeysAreUniqueWithinEachMenu() {
        let cards: [(ClipKind, Bool, String?, String?)] = [
            (.text, true, "{\"a\": [1]}\nmore", nil), (.text, false, "x\ny", nil),
            (.link, true, "https://a.com/?utm_source=x", nil), (.image, false, nil, "text"),
            (.file, false, "/a", nil),
        ]
        for (kind, formatted, text, ocr) in cards {
            let keys = PasteOption.sections(kind: kind, formatted: formatted, text: text, ocr: ocr).flatMap { $0 }.map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, "duplicate key for \(kind)")
            XCTAssertFalse(keys.contains("e"), "e is Copy as File…")
        }
    }

    // MARK: Transforms

    func testCaseChanges() {
        XCTAssertEqual(TextTransform.uppercase.apply("Hello, World"), "HELLO, WORLD")
        XCTAssertEqual(TextTransform.lowercase.apply("Hello, World"), "hello, world")
        XCTAssertEqual(TextTransform.capitalized.apply("hello big world"), "Hello Big World")
    }

    func testTrimWhitespaceKeepsRelativeIndentation() {
        let text = "\n\n    func a() {\n        b()   \n\n\n    }\u{00A0}\n\n"
        XCTAssertEqual(TextTools.trimWhitespace(text), "func a() {\n    b()\n\n}")
    }

    func testTrimWhitespaceNormalizesLineEndings() {
        XCTAssertEqual(TextTools.trimWhitespace("  a \r\n  b\r\n"), "a\nb")
        XCTAssertEqual(TextTools.trimWhitespace("   "), "")
    }

    func testJoinLines() {
        XCTAssertEqual(TextTools.joinLines("This sentence was\n  broken across\r\nlines.\n\n"), "This sentence was broken across lines.")
    }

    func testPrettyJSONKeepsKeyOrderAndNumbers() {
        let json = #"{"zeta":1.50,"alpha":[1,2,{}],"s":"a, b: {c}","e":[],"esc":"q\"x"}"#
        XCTAssertEqual(TextTools.prettyJSON(json), """
        {
          "zeta": 1.50,
          "alpha": [
            1,
            2,
            {}
          ],
          "s": "a, b: {c}",
          "e": [],
          "esc": "q\\"x"
        }
        """)
    }

    func testPrettyJSONRejectsInvalidJSON() {
        XCTAssertNil(TextTools.prettyJSON("{not json}"))
        XCTAssertNil(TextTools.prettyJSON("hello"))
        XCTAssertTrue(TextTools.looksLikeJSON("  [1, 2]\n"))
        XCTAssertFalse(TextTools.looksLikeJSON("[1, 2] and more"))
    }

    func testRemoveTracking() {
        XCTAssertEqual(TextTools.removeTracking("https://shop.example/item?id=7&utm_source=mail&utm_medium=x&fbclid=abc#top"),
                       "https://shop.example/item?id=7#top")
        XCTAssertEqual(TextTools.removeTracking("https://example.com/?gclid=1"), "https://example.com/")
        // "si" is tracking on YouTube, but kept elsewhere; YouTube's "t" (start time) is kept.
        XCTAssertEqual(TextTools.removeTracking("https://youtu.be/abc?si=XYZ&t=42"), "https://youtu.be/abc?t=42")
        XCTAssertNil(TextTools.removeTracking("https://example.com/?si=1"))
        XCTAssertNil(TextTools.removeTracking("https://example.com/page"))
    }

    // MARK: Markdown

    func testMarkdownInlineStyles() {
        let runs = [
            StyledRun("Read "), StyledRun("the docs ", bold: true), StyledRun("now", italic: true),
            StyledRun(", run "), StyledRun("swift test", code: true), StyledRun(" and see "),
            StyledRun("Shelf", link: "https://github.com/lltrx/shelf-clipboard"), StyledRun("."),
        ]
        XCTAssertEqual(MarkdownWriter.markdown(runs),
                       "Read **the docs** *now*, run `swift test` and see [Shelf](https://github.com/lltrx/shelf-clipboard).")
    }

    func testMarkdownMergesNeighboursAndKeepsBareLinks() {
        let runs = [StyledRun("a", bold: true), StyledRun("b", bold: true), StyledRun(" "),
                    StyledRun("https://x.org", link: "https://x.org")]
        XCTAssertEqual(MarkdownWriter.markdown(runs), "**ab** <https://x.org>")
    }

    func testMarkdownParagraphsListsAndCodeBlocks() {
        let runs = [
            StyledRun("Title", bold: true), StyledRun("\nSome text.\n"),
            StyledRun("\t•\tOne\n\t•\t"), StyledRun("Two", italic: true), StyledRun("\n\t\t◦\tNested\n\t1.\tFirst\n"),
            StyledRun("let a = 1\n\n    let b = 2\n", code: true), StyledRun("After"),
        ]
        XCTAssertEqual(MarkdownWriter.markdown(runs), """
        **Title**

        Some text.

        - One
        - *Two*
          - Nested
        1. First

        ```
        let a = 1

            let b = 2
        ```

        After
        """)
    }

    func testMarkdownOfPlainText() {
        XCTAssertEqual(MarkdownWriter.markdown([StyledRun("just text")]), "just text")
        XCTAssertEqual(MarkdownWriter.markdown([]), "")
    }

    // MARK: Colors

    func testHexColors() {
        XCTAssertEqual(ColorText.parse("#FF8000"), .init(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        XCTAssertEqual(ColorText.parse(" #fff\n"), .init(red: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(ColorText.parse("#00000080")?.alpha ?? 0, 128.0 / 255, accuracy: 0.0001)
        XCTAssertNil(ColorText.parse("FF8000"))      // needs the #
        XCTAssertNil(ColorText.parse("#GGGGGG"))
        XCTAssertNil(ColorText.parse("#12345"))
        XCTAssertNil(ColorText.parse("#１２３"))      // fullwidth digits aren't hex here
        XCTAssertNil(ColorText.parse("Color is #FFF"))
    }
}
