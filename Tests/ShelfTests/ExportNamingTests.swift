import XCTest
@testable import Shelf

final class ExportNamingTests: XCTestCase {
    func testSanitize() {
        XCTAssertEqual(ExportNaming.sanitize("  Q3/Q4 report: final\n"), "Q3-Q4 report - final")
        XCTAssertEqual(ExportNaming.sanitize("..hidden"), "hidden")
        XCTAssertEqual(ExportNaming.sanitize("a:b"), "a-b")
        XCTAssertEqual(ExportNaming.sanitize(String(repeating: "x", count: 300)).count, 200)
    }

    func testSplitExtension() {
        XCTAssertEqual(ExportNaming.splitExtension("Report.final.pdf").stem, "Report.final")
        XCTAssertEqual(ExportNaming.splitExtension("Report.final.pdf").ext, "pdf")
        XCTAssertEqual(ExportNaming.splitExtension(".bashrc").ext, "")
        XCTAssertEqual(ExportNaming.splitExtension("Makefile").ext, "")
        XCTAssertEqual(ExportNaming.splitExtension("notes. draft").ext, "")
        XCTAssertNil(ExportNaming.typedExtension("Version 1.2"))
        XCTAssertEqual(ExportNaming.typedExtension("notes.md"), "md")
    }

    private func name(_ typed: String, _ original: String, _ ext: String?, keepTyped: Bool = false) -> String {
        ExportNaming.names(typed: typed, originals: [original], extensions: [ext], keepTypedExtension: keepTyped)[0]
    }

    func testSingleFileNames() {
        XCTAssertEqual(name("Beach", "IMG_0001.HEIC", "jpg"), "Beach.jpg")
        XCTAssertEqual(name("Beach", "IMG_0001.HEIC", nil), "Beach.HEIC")             // keep format
        XCTAssertEqual(name("Beach.jpeg", "IMG_0001.HEIC", "jpg"), "Beach.jpeg")       // already right
        XCTAssertEqual(name("Beach.png", "IMG_0001.HEIC", "jpg"), "Beach.jpg")         // typed format replaced
        XCTAssertEqual(name("Beach.heic", "IMG_0001.HEIC", nil), "Beach.heic")
        XCTAssertEqual(name("Version 1.2", "a.pdf", nil), "Version 1.2.pdf")
        XCTAssertEqual(name("my.backup", "a.pdf", nil), "my.backup.pdf")               // not a format
        XCTAssertEqual(name("", "IMG_0001.HEIC", "png"), "IMG_0001.png")               // empty keeps the name
        XCTAssertEqual(name("folder", "Projects", nil), "folder")                      // no extension at all
    }

    func testPlainTextKeepsTypedExtension() {
        XCTAssertEqual(name("deploy.sh", "Text.txt", "txt", keepTyped: true), "deploy.sh")
        XCTAssertEqual(name("data.csv", "Text.txt", "txt", keepTyped: true), "data.csv")
        XCTAssertEqual(name("notes", "Text.txt", "txt", keepTyped: true), "notes.txt")
        XCTAssertEqual(name("notes.txt", "Text.txt", "md"), "notes.md")
    }

    func testSeveralFiles() {
        let originals = ["a.png", "b.HEIC", "c.pdf"]
        // Converting to JPEG applies to the images only.
        XCTAssertEqual(ExportNaming.names(typed: "", originals: originals, extensions: ["jpg", "jpg", nil]),
                       ["a.jpg", "b.jpg", "c.pdf"])
        XCTAssertEqual(ExportNaming.names(typed: "Trip", originals: originals, extensions: ["jpg", "jpg", nil]),
                       ["Trip 1.jpg", "Trip 2.jpg", "Trip 3.pdf"])
    }

    func testNamesAreMadeUnique() {
        XCTAssertEqual(ExportNaming.names(typed: "", originals: ["a.png", "a.jpg", "A.gif"], extensions: ["jpg", "jpg", "jpg"]),
                       ["a.jpg", "a 2.jpg", "A 3.jpg"])
        XCTAssertEqual(ExportNaming.uniqued(["x.txt", "y"], existing: ["X.txt", "y", "y 2"]), ["x 2.txt", "y 3"])
    }

    func testSuggestedNameFromText() {
        XCTAssertEqual(ExportNaming.suggestedName(forText: "\n\n  Meeting   notes: Monday\nmore"), "Meeting notes - Monday")
        XCTAssertEqual(ExportNaming.suggestedName(forText: "The quick brown fox jumps over the lazy dog again and again"),
                       "The quick brown fox jumps over the lazy")
        XCTAssertEqual(ExportNaming.suggestedName(forText: "Done."), "Done")
        XCTAssertNil(ExportNaming.suggestedName(forText: " \n\t"))
    }

    func testTimestampName() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC
        XCTAssertEqual(ExportNaming.timestampName("Image", date, timeZone: TimeZone(identifier: "UTC")!),
                       "Image 2023-11-14 at 22.13.20")
    }

    private func draft(_ originals: [String], _ convertible: [Bool], _ format: ExportFormat, name: String = "") -> ExportDraft {
        let item = ClipItem(id: 1, kind: .file, text: nil, image: nil, detail: nil, sourceBundle: nil, sourceName: nil,
                            created: Date(), board: nil, formatted: false, ocr: nil)
        return ExportDraft(item: item, source: .files, originals: originals, convertible: convertible,
                           formats: [.original, .jpeg], name: name, format: format)
    }

    func testDraftNamesAndSummary() {
        let d = draft(["a.png", "b.pdf", "c.png", "d.png"], [true, false, true, true], .jpeg)
        XCTAssertEqual(d.fileNames, ["a.jpg", "b.pdf", "c.jpg", "d.jpg"])
        XCTAssertEqual(d.namesSummary, "a.jpg, b.pdf and 2 more")
        XCTAssertTrue(d.showsImageOptions)
        XCTAssertFalse(draft(["a.png"], [true], .original).showsImageOptions)
        XCTAssertFalse(draft(["b.pdf"], [false], .jpeg).showsImageOptions)
        XCTAssertEqual(draft(["IMG_1.HEIC"], [true], .jpeg, name: "Cat").namesSummary, "Cat.jpg")
    }

    func testFormatExtensions() {
        XCTAssertEqual(ExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertNil(ExportFormat.original.fileExtension)
        XCTAssertEqual(ExportFormat.docx.fileExtension, "docx")
        XCTAssertTrue(ExportFormat.heic.isLossy)
        XCTAssertFalse(ExportFormat.png.isLossy)
        XCTAssertTrue(ExportFormat.pdf.isImage)
        XCTAssertFalse(ExportFormat.md.isImage)
    }
}
