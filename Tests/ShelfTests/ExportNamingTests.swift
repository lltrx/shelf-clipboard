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

    private func draft(_ originals: [String], _ convertible: [Bool], _ format: ExportFormat, name: String = "",
                       formats: [ExportFormat] = [.original, .jpeg]) -> ExportDraft {
        let item = ClipItem(id: 1, kind: .file, text: nil, image: nil, detail: nil, sourceBundle: nil, sourceName: nil,
                            created: Date(), board: nil, formatted: false, ocr: nil)
        return ExportDraft(item: item, source: .files, originals: originals, convertible: convertible,
                           formats: formats, name: name, format: format)
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

    func testFormatOfAFile() {
        XCTAssertEqual(ExportFormat.of(extension: "JPEG"), .jpeg)
        XCTAssertEqual(ExportFormat.of(extension: "heif"), .heic)
        XCTAssertEqual(ExportFormat.of(extension: "png"), .png)
        XCTAssertNil(ExportFormat.of(extension: "pdf"))     // not an image Shelf converts from
        XCTAssertNil(ExportFormat.of(extension: "webp"))    // readable, but not written
    }

    func testPasteBoxPastesTheOriginalUntilSomethingChanges() {
        var d = draft(["shot.png"], [true], .png, name: "shot")
        d.startName = "shot"
        d.startFormat = .png
        XCTAssertTrue(d.pastesOriginal)
        d.scale = 0.5
        XCTAssertFalse(d.pastesOriginal)
        d.scale = 1
        d.name = "invoice"
        XCTAssertFalse(d.pastesOriginal)
        d.name = "shot"
        d.format = .jpeg
        XCTAssertFalse(d.pastesOriginal)
    }

    func testTextAlwaysBecomesAFile() {
        let item = ClipItem(id: 2, kind: .text, text: "hi", image: nil, detail: nil, sourceBundle: nil, sourceName: nil,
                            created: Date(), board: nil, formatted: false, ocr: nil)
        let d = ExportDraft(item: item, source: .text, originals: ["hi.txt"], convertible: [true], formats: ExportFormat.text,
                            name: "hi", format: .txt, startName: "hi", startFormat: .txt)
        XCTAssertTrue(d.isUnchanged)
        XCTAssertFalse(d.pastesOriginal)
        XCTAssertFalse(d.hasImages)
        XCTAssertEqual(d.popoverHeight, 156)
    }

    func testImagesGetASizeRow() {
        XCTAssertTrue(draft(["a.png", "b.pdf"], [true, false], .original).hasImages)
        XCTAssertFalse(draft(["b.pdf"], [false], .original).hasImages)
        XCTAssertEqual(draft(["a.png"], [true], .png).popoverHeight, 193)
    }

    func testQualitySnapsToASteps() {
        XCTAssertEqual(ExportDraft.nearestQuality(0.87), 0.9, accuracy: 0.001)
        XCTAssertEqual(ExportDraft.nearestQuality(0.78), 0.8, accuracy: 0.001)
        XCTAssertEqual(ExportDraft.nearestQuality(0.05), 0.3, accuracy: 0.001)
        XCTAssertTrue(ExportDraft.qualities.contains(ExportDraft(item: ClipItem(id: 1, kind: .image, text: nil, image: nil,
            detail: nil, sourceBundle: nil, sourceName: nil, created: Date(), board: nil, formatted: false, ocr: nil),
            source: .image, originals: ["a.png"], convertible: [true], formats: [.png], name: "a", format: .png).quality))
    }

    func testTabGoesThroughTheControlsShown() {
        var d = draft(["shot.png"], [true], .png, formats: [.png, .jpeg, .heic])
        XCTAssertEqual(d.fields, [.name, .format, .size])
        d.format = .jpeg
        XCTAssertEqual(d.fields, [.name, .format, .size, .quality])
        XCTAssertEqual(d.field(after: .name), .format)
        XCTAssertEqual(d.field(after: .quality), .name)                 // wraps around
        XCTAssertEqual(d.field(after: .name, backward: true), .quality)
        XCTAssertEqual(draft(["a.pdf"], [false], .original, formats: [.original]).fields, [.name])   // nothing else to reach
        XCTAssertEqual(draft(["a.png"], [true], .original).fields, [.name, .format])   // Keep Format: no Size
    }

    func testArrowsChangeTheFocusedControl() {
        var d = draft(["shot.png"], [true], .png, formats: [.png, .jpeg, .heic])
        d.change(.size, .right)
        XCTAssertEqual(d.scale, 0.75)
        d.change(.size, .right); d.change(.size, .right); d.change(.size, .right)
        XCTAssertEqual(d.scale, 0.25)                                   // stops at the end
        d.change(.size, .up)
        XCTAssertEqual(d.scale, 0.5)

        d.change(.format, .down)                                       // formats here: PNG, JPEG, HEIC
        XCTAssertEqual(d.format, .jpeg)
        d.change(.format, .right)
        d.change(.format, .down)
        XCTAssertEqual(d.format, .heic)                                // stops at the end
        d.change(.format, .left)
        XCTAssertEqual(d.format, .jpeg)

        d.format = .jpeg
        d.quality = 0.8
        d.change(.quality, .right)
        XCTAssertEqual(d.quality, 0.9, accuracy: 0.001)
        d.change(.quality, .down)
        d.change(.quality, .left)
        XCTAssertEqual(d.quality, 0.7, accuracy: 0.001)
        d.change(.name, .left)                                         // the text field's own business
        XCTAssertEqual(d.quality, 0.7, accuracy: 0.001)
    }

    func testEditsCountAsAChange() {
        var d = draft(["shot.png"], [true], .png, formats: [.png, .jpeg])
        d.startName = ""
        d.startFormat = .png
        XCTAssertTrue(d.pastesOriginal)
        XCTAssertTrue(d.canEdit)
        d.edits.blurs.append(EditRect(x: 0.1, y: 0.1, w: 0.2, h: 0.1))
        XCTAssertFalse(d.pastesOriginal)
        XCTAssertEqual(d.edits.summary, "1 area hidden")
        d.edits.crop = EditRect(x: 0, y: 0, w: 0.5, h: 0.5)
        XCTAssertEqual(d.edits.summary, "1 area hidden, cropped")
    }

    func testEditedImageKeepingItsFormatIsWrittenAsPNG() {
        var d = draft(["photo.webp"], [true], .original, formats: [.original, .png])
        XCTAssertEqual(d.outputFormat, .original)
        XCTAssertEqual(d.fileNames, ["photo.webp"])
        d.edits.crop = EditRect(x: 0.2, y: 0.2, w: 0.5, h: 0.5)
        XCTAssertEqual(d.outputFormat, .png)
        XCTAssertEqual(d.fileNames, ["photo.png"])
    }

    func testOnlyASingleImageCanBeEdited() {
        XCTAssertFalse(draft(["a.png", "b.png"], [true, true], .png).canEdit)
        XCTAssertFalse(draft(["a.pdf"], [false], .original).canEdit)
    }

    func testEditRectStaysInsideTheImage() {
        XCTAssertEqual(EditRect(x: -0.25, y: 0.5, w: 0.5, h: 0.75).clamped, EditRect(x: 0, y: 0.5, w: 0.25, h: 0.5))
        XCTAssertNil(EditRect(x: 1.2, y: 0, w: 0.3, h: 0.3).clamped)
    }

    func testEditorAddsUndoesAndCancels() {
        var d = draft(["shot.png"], [true], .png, formats: [.png, .jpeg])
        d.addEdit(EditRect(x: 0, y: 0, w: 0.5, h: 0.5))             // the editor isn't open
        XCTAssertTrue(d.edits.isEmpty)

        d.beginEditing()
        XCTAssertEqual(d.editor?.tool, .arrow)                      // the editor opens on Arrow
        d.editor?.tool = .blur
        d.addEdit(EditRect(x: 0.1, y: 0.1, w: 0.2, h: 0.1))
        d.addEdit(EditRect(x: 0.5, y: 0.5, w: 0.004, h: 0.3))       // a click: ignored
        d.addEdit(EditRect(x: 0.6, y: 0.6, w: 0.2, h: 0.2))
        XCTAssertEqual(d.edits.blurs.count, 2)
        d.editor?.tool = .crop
        d.addEdit(EditRect(x: 0, y: 0, w: 0.9, h: 0.9))
        d.addEdit(EditRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8))          // a new crop replaces the old one
        XCTAssertEqual(d.edits.crop, EditRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8))
        d.undoEdit()
        XCTAssertEqual(d.edits.crop, EditRect(x: 0, y: 0, w: 0.9, h: 0.9))
        d.clearEdits()
        XCTAssertTrue(d.edits.isEmpty)
        d.undoEdit()
        XCTAssertEqual(d.edits.blurs.count, 2)
        d.endEditing(keep: true)
        XCTAssertNil(d.editor)
        XCTAssertEqual(d.edits.blurs.count, 2)

        d.beginEditing()                                            // again, then Esc: as it was
        d.addEdit(EditRect(x: 0.2, y: 0.2, w: 0.3, h: 0.3))
        d.endEditing(keep: false)
        XCTAssertEqual(d.edits.blurs.count, 2)
    }

    func testMarksAndText() {
        var d = draft(["shot.png"], [true], .png, formats: [.png, .jpeg])
        d.beginEditing()
        d.addDrag(from: EditPoint(x: 0.1, y: 0.1), to: EditPoint(x: 0.4, y: 0.3))              // an arrow
        d.addDrag(from: EditPoint(x: 0.5, y: 0.5), to: EditPoint(x: 0.5, y: 0.505))            // too short
        XCTAssertEqual(d.edits.marks.count, 1)
        XCTAssertEqual(d.edits.marks[0].kind, .arrow)
        XCTAssertEqual(d.edits.marks[0].color, .red)

        d.editor?.tool = .highlight
        d.editor?.color = .blue                                                                // ignored: always yellow
        d.addDrag(from: EditPoint(x: 0.75, y: 0.25), to: EditPoint(x: 0.25, y: 0.375))
        XCTAssertEqual(d.edits.marks[1].color, .yellow)
        XCTAssertEqual(d.edits.marks[1].rect, EditRect(x: 0.25, y: 0.25, w: 0.5, h: 0.125))

        d.editor?.tool = .box
        d.addDrag(from: EditPoint(x: -0.5, y: 0.875), to: EditPoint(x: 0.25, y: 1.5))          // kept inside the image
        XCTAssertEqual(d.edits.marks[2].rect, EditRect(x: 0, y: 0.875, w: 0.25, h: 0.125))
        XCTAssertEqual(d.edits.marks[2].color, .blue)
        XCTAssertEqual(d.edits.summary, "3 marks")

        d.editor?.tool = .text
        d.addDrag(from: EditPoint(x: 0.3, y: 0.3), to: EditPoint(x: 0.3, y: 0.3))              // a click
        XCTAssertEqual(d.editor?.typing, 3)
        d.typeText("Look here")
        XCTAssertEqual(d.typedText, "Look here")
        d.finishTyping(keep: true)
        XCTAssertNil(d.editor?.typing)
        XCTAssertEqual(d.edits.marks.last?.text, "Look here")

        d.addDrag(from: EditPoint(x: 0.7, y: 0.7), to: EditPoint(x: 0.7, y: 0.7))
        d.finishTyping(keep: true)                                                             // nothing typed: gone
        XCTAssertEqual(d.edits.marks.count, 4)
        d.addDrag(from: EditPoint(x: 0.7, y: 0.7), to: EditPoint(x: 0.7, y: 0.7))
        d.typeText("oops")
        d.undoEdit()                                                                           // ⌘Z while typing
        XCTAssertEqual(d.edits.marks.count, 4)
        d.undoEdit()                                                                           // then the text before
        XCTAssertEqual(d.edits.marks.count, 3)
        XCTAssertFalse(d.pastesOriginal)
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
