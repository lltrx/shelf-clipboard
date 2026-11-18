import Foundation

// Copy as File (⌘R): what a card becomes as a file, and what that file is called.
// Foundation only, so it can be unit tested without the UI. The conversion itself is in FileExport.swift.

/// File formats offered in Copy as File.
enum ExportFormat: String, CaseIterable, Identifiable {
    case original                                  // files: keep their own format, just rename
    case png, jpeg, heic, tiff, gif, pdf           // images
    case txt, md, rtf, docx, html                  // text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Keep Format"
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .pdf: return "PDF"
        case .txt: return "Plain Text"
        case .md: return "Markdown"
        case .rtf: return "Rich Text (RTF)"
        case .docx: return "Word Document"
        case .html: return "Web Page (HTML)"
        }
    }

    /// The extension new files get; nil keeps each file's own.
    var fileExtension: String? {
        switch self {
        case .original: return nil
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }

    /// Has a quality setting.
    var isLossy: Bool { self == .jpeg || self == .heic }
    var isImage: Bool { ExportFormat.image.contains(self) }

    static let image: [ExportFormat] = [.png, .jpeg, .heic, .tiff, .gif, .pdf]
    static let text: [ExportFormat] = [.txt, .md, .rtf, .docx, .html]

    /// The image format a file already has, from its extension, if Shelf can write it.
    static func of(extension ext: String) -> ExportFormat? {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "gif": return .gif
        default: return nil
        }
    }
}

enum ExportNaming {
    /// Extensions that name a format, so a typed "photo.png" saved as JPEG becomes "photo.jpg",
    /// not "photo.png.jpg".
    static let knownExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "pdf", "bmp", "webp",
        "txt", "md", "rtf", "doc", "docx", "htm", "html",
    ]

    /// A name macOS accepts: no "/" or ":", no control characters, not hidden (leading dot), not too long.
    static func sanitize(_ name: String) -> String {
        var s = name.components(separatedBy: .controlCharacters).joined()
        s = s.replacingOccurrences(of: ": ", with: " - ")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.count > 200 ? String(s.prefix(200)) : s
    }

    /// "Report.final.pdf" → ("Report.final", "pdf"). Names without one, or starting with a dot, have none.
    static func splitExtension(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[name.index(after: dot)...])
        guard !ext.isEmpty, ext.count <= 12, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return (name, "") }
        return (String(name[..<dot]), ext)
    }

    /// The extension someone typed, if it looks like one: "notes.md" has one, "Version 1.2" doesn't.
    static func typedExtension(_ name: String) -> String? {
        let ext = splitExtension(name).ext
        return ext.contains(where: \.isLetter) ? ext : nil
    }

    /// The final file names.
    /// - typed: the name in the form. Empty keeps the original names. With several files, they are numbered.
    /// - originals: the original file names (a made-up one for images and text).
    /// - extensions: for each original, the new extension, or nil to keep its own.
    /// - keepTypedExtension: plain text keeps whatever extension is typed ("deploy.sh", "data.csv").
    static func names(typed: String, originals: [String], extensions: [String?], keepTypedExtension: Bool = false) -> [String] {
        let base = sanitize(typed)
        let names = originals.enumerated().map { i, original -> String in
            let (originalStem, originalExt) = splitExtension(original)
            let ext = (i < extensions.count ? extensions[i] : nil) ?? (originalExt.isEmpty ? nil : originalExt)
            let stem: String
            if base.isEmpty {
                stem = originalStem
            } else if originals.count > 1 {
                stem = "\(base) \(i + 1)"
            } else if let typedExt = typedExtension(base) {
                if keepTypedExtension || ext.map({ sameExtension(typedExt, $0) }) == true { return base }
                let isFormat = knownExtensions.contains(typedExt.lowercased()) || sameExtension(typedExt, originalExt)
                stem = isFormat ? splitExtension(base).stem : base
            } else {
                stem = base
            }
            return ext.map { "\(stem).\($0)" } ?? stem
        }
        return uniqued(names)
    }

    private static func sameExtension(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        let synonyms: [Set<String>] = [["jpg", "jpeg"], ["tif", "tiff"], ["htm", "html"], ["heic", "heif"]]
        return a == b || synonyms.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Makes names unique (ignoring case, as macOS does) by adding " 2", " 3"…, also avoiding `existing`.
    static func uniqued(_ names: [String], existing: Set<String> = []) -> [String] {
        var taken = Set(existing.map { $0.lowercased() })
        return names.map { name in
            let (stem, ext) = splitExtension(name)
            var candidate = name
            var n = 2
            while taken.contains(candidate.lowercased()) {
                candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
                n += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }

    /// A file name from the first line of some text: "Meeting notes", at most about 40 characters.
    static func suggestedName(forText text: String) -> String? {
        let firstLine = text.prefix(2000).split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { !$0.isEmpty }
        guard let line = firstLine else { return nil }
        var name = sanitize(line)
        if name.count > 40 {
            let cut = String(name.prefix(40))
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= 15 {
                name = String(cut[..<space])
            } else {
                name = cut
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .,;-"))
        return name.isEmpty ? nil : name
    }

    /// "Image 2026-11-16 at 19.40.12", like macOS names screenshots. Western digits in any locale.
    static func timestampName(_ prefix: String, _ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(f.string(from: date))"
    }
}

/// The buttons of the paste box: Return, ⌘C and ⌘S.
enum ExportAction { case paste, copy, save }

/// The paste box's controls, in Tab order.
enum ExportField: Equatable { case name, format, size, quality, markup }

/// What's selected in the image editor, to move, resize, recolor or delete with the keyboard.
enum EditSelection: Equatable {
    case mark(Int)   // an index into edits.marks
    case blur(Int)   // an index into edits.blurs
    case crop
}

/// The image editor's tools: Blur pixelates the area dragged over, Crop keeps only it; Arrow, Box,
/// Highlight and Text draw on the image.
enum EditTool: Equatable, CaseIterable {
    case arrow, box, highlight, text, blur, crop

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .highlight: return "Highlight"
        case .text: return "Text"
        case .blur: return "Blur"
        case .crop: return "Crop"
        }
    }

    /// The letter that picks it (physical key code, so any keyboard layout works).
    var letter: String {
        switch self {
        case .arrow: return "A"
        case .box: return "R"
        case .highlight: return "H"
        case .text: return "T"
        case .blur: return "B"
        case .crop: return "C"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .arrow: return 0
        case .box: return 15
        case .highlight: return 4
        case .text: return 17
        case .blur: return 11
        case .crop: return 8
        }
    }

    /// What to do with it, for the editor's bottom line.
    var instruction: String {
        switch self {
        case .arrow: return "Drag from where the arrow starts to what it points at"
        case .box: return "Drag around something to draw a box"
        case .highlight: return "Drag over text to highlight it"
        case .text: return "Click where the text goes, type, then Return"
        case .blur: return "Drag over what to hide"
        case .crop: return "Drag around what to keep"
        }
    }

    /// Draws in the chosen color (Highlight is always yellow).
    var usesColor: Bool { self == .arrow || self == .box || self == .text }
}

/// The colors marks can be drawn in.
enum MarkColor: String, CaseIterable, Equatable {
    case red, orange, yellow, green, blue, white, black

    /// sRGB, 0…1.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: return (1.0, 0.23, 0.19)
        case .orange: return (1.0, 0.58, 0.0)
        case .yellow: return (1.0, 0.84, 0.04)
        case .green: return (0.2, 0.78, 0.35)
        case .blue: return (0.0, 0.48, 1.0)
        case .white: return (1, 1, 1)
        case .black: return (0, 0, 0)
        }
    }

    /// Text gets an outline in the opposite tone, so it reads on any background.
    var isLight: Bool { self == .white || self == .yellow }
}

/// A point of an image, as fractions of its width and height from the top left.
struct EditPoint: Equatable {
    var x: Double
    var y: Double

    var clamped: EditPoint { EditPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)) }

    func distance(to other: EditPoint) -> Double { ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot() }
}

/// Something drawn on the image: an arrow from `from` to `to`, a box or highlight between them, or
/// text whose top left is `from`.
struct ImageMark: Equatable {
    enum Kind: Equatable { case arrow, box, highlight, text }

    var kind: Kind
    var from: EditPoint
    var to: EditPoint
    var color: MarkColor
    var text = ""

    /// The area between the two points (boxes and highlights).
    var rect: EditRect {
        EditRect(x: min(from.x, to.x), y: min(from.y, to.y), w: abs(to.x - from.x), h: abs(to.y - from.y))
    }
}

/// An area of an image, as fractions of its width and height from the top left (0…1), so it holds
/// at any size.
struct EditRect: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    /// The same area kept inside the image, or nil if nothing of it is.
    var clamped: EditRect? {
        let left = max(0, x), top = max(0, y)
        let right = min(1, x + w), bottom = min(1, y + h)
        guard right > left, bottom > top else { return nil }
        return EditRect(x: left, y: top, w: right - left, h: bottom - top)
    }
}

extension String {
    /// "Cropped" for "cropped".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// What the image editor did: areas to pixelate, then an area to keep.
struct ImageEdits: Equatable {
    var blurs: [EditRect] = []
    var crop: EditRect?
    var marks: [ImageMark] = []   // drawn after the blurs, before the crop

    var isEmpty: Bool { blurs.isEmpty && crop == nil && marks.isEmpty }

    /// Smaller than this (a click, or a slip of the mouse) isn't an area.
    static let smallest = 0.01

    /// "2 marks, 1 area hidden, cropped"
    var summary: String {
        var parts: [String] = []
        if !marks.isEmpty { parts.append(marks.count == 1 ? "1 mark" : "\(marks.count) marks") }
        if !blurs.isEmpty { parts.append(blurs.count == 1 ? "1 area hidden" : "\(blurs.count) areas hidden") }
        if crop != nil { parts.append("cropped") }
        return parts.joined(separator: ", ")
    }

    /// What the editor's preview shows: everything but the crop (shown as a frame instead).
    var uncropped: ImageEdits { ImageEdits(blurs: blurs, crop: nil, marks: marks) }
}

/// The Copy as File form: what is being made, and the choices so far.
struct ExportDraft: Equatable {
    enum Source: Equatable { case image, text, files }

    let id = UUID()               // tells this form from one reopened later for the same card
    let item: ClipItem
    let source: Source
    let originals: [String]       // original file names; one made-up name for an image or text card
    let convertible: [Bool]       // for each original: whether the format choice applies to it
    let formats: [ExportFormat]   // choices in the Format menu
    var name: String
    var format: ExportFormat
    var quality = 0.8             // JPEG and HEIC: one of `qualities`
    var scale = 1.0               // images: 1, 0.75, 0.5 or 0.25 of the original size
    var busy = false
    var error: String?
    var startName: String?        // what the box opened with, to tell whether anything changed
    var startFormat: ExportFormat?
    var edits = ImageEdits()      // blurred and cropped areas (a single image only)
    var editor: Editor?           // the blur and crop editor, while it's open

    /// The editor's state: the tool, what to put back on Esc, and the steps Undo goes through.
    struct Editor: Equatable {
        var tool: EditTool = .arrow
        var color: MarkColor = .red
        var before: ImageEdits
        var history: [ImageEdits] = []
        var typing: Int?              // the text mark being typed, as an index into edits.marks
        var selected: EditSelection?
        var nudging = false           // in a run of arrow-key moves, which Undo takes back as one step
        var canUndo: Bool { !history.isEmpty }
    }

    var openedForMarkup = false       // ⌘E on a card: Esc in the editor closes the whole box

    static let qualities: [Double] = [1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3]
    static let scales: [Double] = [1, 0.75, 0.5, 0.25]

    /// The quality step nearest to `value` (a remembered quality may be between steps).
    static func nearestQuality(_ value: Double) -> Double {
        qualities.min { abs($0 - value) < abs($1 - value) } ?? 0.8
    }

    /// Images among the sources, so Size (and Quality) apply.
    var hasImages: Bool { source != .text && convertible.contains(true) }

    /// Nothing changed since the box opened.
    var isUnchanged: Bool {
        name == (startName ?? name) && format == (startFormat ?? format) && scale == 1 && edits.isEmpty
    }

    /// Return pastes the card as it is: an image or file nobody renamed, resized or converted.
    /// (Text opened with ⌘R always becomes a file: that's what ⌘R asked for.)
    var pastesOriginal: Bool { source != .text && isUnchanged }

    /// Height of the paste box in points, its arrow included: Size takes a row when there are images.
    var popoverHeight: Double { hasImages ? 193 : 156 }

    // MARK: Blur and crop

    mutating func beginEditing() {
        guard canEdit, editor == nil else { return }
        editor = Editor(before: edits)
    }

    /// An area dragged out with Blur (adds one) or Crop (replaces the crop).
    mutating func addEdit(_ rect: EditRect) {
        guard var e = editor, e.tool == .blur || e.tool == .crop, let area = rect.clamped,
              area.w >= ImageEdits.smallest, area.h >= ImageEdits.smallest else { return }
        e.history.append(edits)
        if e.tool == .blur {
            edits.blurs.append(area)
            e.selected = .blur(edits.blurs.count - 1)
        } else {
            edits.crop = area
            e.selected = .crop
        }
        e.nudging = false
        editor = e
    }

    /// A drag on the image with the current tool, from where the mouse went down to where it came
    /// up (the same point for a click). Text starts typing at a click.
    mutating func addDrag(from start: EditPoint, to end: EditPoint, aspect: Double = 1) {
        finishTyping(keep: true)
        guard var e = editor else { return }
        let a = start.clamped, b = end.clamped
        e.nudging = false
        // A click on something already there selects it (so the arrow keys can move it); a click on
        // nothing lets go of the selection, or, with Text, starts typing there. (With Text, only
        // other text is picked by a click, so text can go on top of a highlight or a box.)
        if a.distance(to: b) < ImageEdits.smallest / 2 {
            if let hit = item(at: b, aspect: aspect), e.tool != .text || isText(hit) {
                e.selected = hit
                editor = e
                return
            }
            e.selected = nil
            editor = e
            if e.tool != .text { return }
        }
        switch e.tool {
        case .blur, .crop:
            addEdit(EditRect(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(b.x - a.x), h: abs(b.y - a.y)))
        case .arrow:
            guard a.distance(to: b) >= ImageEdits.smallest * 2 else { return }
            e.history.append(edits)
            edits.marks.append(ImageMark(kind: .arrow, from: a, to: b, color: e.color))
            e.selected = .mark(edits.marks.count - 1)
            editor = e
        case .box, .highlight:
            let mark = ImageMark(kind: e.tool == .box ? .box : .highlight, from: a, to: b,
                                 color: e.tool == .highlight ? .yellow : e.color)
            guard mark.rect.w >= ImageEdits.smallest, mark.rect.h >= ImageEdits.smallest else { return }
            e.history.append(edits)
            edits.marks.append(mark)
            e.selected = .mark(edits.marks.count - 1)
            editor = e
        case .text:
            e.history.append(edits)
            edits.marks.append(ImageMark(kind: .text, from: b, to: b, color: e.color))
            e.typing = edits.marks.count - 1
            e.selected = .mark(edits.marks.count - 1)
            editor = e
        }
    }

    /// The text being typed, as it changes.
    mutating func typeText(_ text: String) {
        guard let i = editor?.typing, edits.marks.indices.contains(i) else { return }
        edits.marks[i].text = text
    }

    var typedText: String {
        guard let i = editor?.typing, edits.marks.indices.contains(i) else { return "" }
        return edits.marks[i].text
    }

    /// Return keeps the text (unless nothing was typed); Esc takes it away.
    mutating func finishTyping(keep: Bool) {
        guard var e = editor, let i = e.typing else { return }
        e.typing = nil
        let empty = !edits.marks.indices.contains(i) || edits.marks[i].text.trimmingCharacters(in: .whitespaces).isEmpty
        if (!keep || empty), let before = e.history.popLast() {
            edits = before
            if case .mark(let s)? = e.selected, !edits.marks.indices.contains(s) { e.selected = nil }   // the text is gone
        }
        e.nudging = false
        editor = e
    }

    mutating func undoEdit() {
        if editor?.typing != nil { finishTyping(keep: false); return }
        guard let previous = editor?.history.popLast() else { return }
        edits = previous
        editor?.selected = nil
        editor?.nudging = false
    }

    // MARK: Markup with the keyboard

    /// A tool picked (by its letter or its button). Whatever was selected is let go.
    mutating func setTool(_ tool: EditTool) {
        finishTyping(keep: true)
        editor?.tool = tool
        editor?.selected = nil
        editor?.nudging = false
    }

    /// A color picked (1–7, or a swatch). A selected arrow, box or text takes it too.
    mutating func setColor(_ color: MarkColor) {
        guard var e = editor else { return }
        e.color = color
        if case .mark(let i)? = e.selected, edits.marks.indices.contains(i),
           edits.marks[i].kind != .highlight, edits.marks[i].color != color {
            e.history.append(edits)
            e.nudging = false
            edits.marks[i].color = color
        }
        editor = e
    }

    /// Everything that can be selected, in Tab order: marks as drawn, then blurred areas, then the crop.
    var selectables: [EditSelection] {
        edits.marks.indices.map { .mark($0) } + edits.blurs.indices.map { .blur($0) } + (edits.crop == nil ? [] : [.crop])
    }

    mutating func select(_ selection: EditSelection?) {
        finishTyping(keep: true)
        let all = selectables
        editor?.selected = selection.flatMap { all.contains($0) ? $0 : nil }
        editor?.nudging = false
    }

    /// Tab (⇧Tab): the next (previous) item, wrapping around.
    mutating func selectNext(backward: Bool = false) {
        finishTyping(keep: true)
        let all = selectables
        guard editor != nil, !all.isEmpty else { return }
        if let current = editor?.selected, let i = all.firstIndex(of: current) {
            editor?.selected = all[(i + (backward ? -1 : 1) + all.count) % all.count]
        } else {
            editor?.selected = backward ? all[all.count - 1] : all[0]
        }
        editor?.nudging = false
    }

    /// Space: one of the current tool's marks in the middle of the image, selected, ready for the
    /// arrow keys. With Text, typing starts.
    mutating func addInMiddle() {
        finishTyping(keep: true)
        guard var e = editor else { return }
        e.history.append(edits)
        e.nudging = false
        func mark(_ kind: ImageMark.Kind, _ from: (Double, Double), _ to: (Double, Double), _ color: MarkColor) {
            edits.marks.append(ImageMark(kind: kind, from: EditPoint(x: from.0, y: from.1), to: EditPoint(x: to.0, y: to.1), color: color))
            e.selected = .mark(edits.marks.count - 1)
        }
        switch e.tool {
        case .arrow: mark(.arrow, (0.35, 0.65), (0.5, 0.5), e.color)
        case .box: mark(.box, (0.35, 0.35), (0.65, 0.65), e.color)
        case .highlight: mark(.highlight, (0.3, 0.47), (0.7, 0.53), .yellow)
        case .text:
            mark(.text, (0.4, 0.45), (0.4, 0.45), e.color)
            e.typing = edits.marks.count - 1
        case .blur:
            edits.blurs.append(EditRect(x: 0.35, y: 0.45, w: 0.3, h: 0.1))
            e.selected = .blur(edits.blurs.count - 1)
        case .crop:
            edits.crop = EditRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8)
            e.selected = .crop
        }
        editor = e
    }

    /// Return on a selected text: type to change it (Return keeps it, Esc puts the old text back).
    /// False when no text is selected.
    mutating func editSelectedText() -> Bool {
        guard var e = editor, e.typing == nil, case .mark(let i)? = e.selected,
              edits.marks.indices.contains(i), edits.marks[i].kind == .text else { return false }
        e.history.append(edits)
        e.typing = i
        e.nudging = false
        editor = e
        return true
    }

    /// The arrow keys: moves the selected item, keeping it inside the image. A run of moves (and
    /// resizes) is one Undo step.
    mutating func moveSelected(dx: Double, dy: Double) {
        guard var e = editor, let selection = e.selected else { return }
        func fit(_ d: Double, _ values: [Double]) -> Double { min(max(d, -(values.min() ?? 0)), 1 - (values.max() ?? 1)) }
        func moved(_ r: EditRect) -> EditRect {
            EditRect(x: r.x + fit(dx, [r.x, r.x + r.w]), y: r.y + fit(dy, [r.y, r.y + r.h]), w: r.w, h: r.h)
        }
        let before = edits
        switch selection {
        case .mark(let i) where edits.marks.indices.contains(i):
            var m = edits.marks[i]
            let mx = fit(dx, [m.from.x, m.to.x]), my = fit(dy, [m.from.y, m.to.y])
            m.from = EditPoint(x: m.from.x + mx, y: m.from.y + my)
            m.to = EditPoint(x: m.to.x + mx, y: m.to.y + my)
            edits.marks[i] = m
        case .blur(let i) where edits.blurs.indices.contains(i):
            edits.blurs[i] = moved(edits.blurs[i])
        case .crop:
            if let crop = edits.crop { edits.crop = moved(crop) }
        default:
            e.selected = nil
        }
        if edits != before, !e.nudging {
            e.history.append(before)
            e.nudging = true
        }
        editor = e
    }

    /// ⌥ and the arrow keys: a box, highlight, blur or crop grows or shrinks from its bottom right
    /// corner; an arrow's head moves. Text keeps its size.
    mutating func resizeSelected(dw: Double, dh: Double) {
        guard var e = editor, let selection = e.selected else { return }
        func resized(_ r: EditRect) -> EditRect {
            let smallest = ImageEdits.smallest * 2
            return EditRect(x: r.x, y: r.y, w: min(max(r.w + dw, smallest), 1 - r.x), h: min(max(r.h + dh, smallest), 1 - r.y))
        }
        let before = edits
        switch selection {
        case .mark(let i) where edits.marks.indices.contains(i):
            var m = edits.marks[i]
            switch m.kind {
            case .arrow:
                m.to = EditPoint(x: m.to.x + dw, y: m.to.y + dh).clamped
            case .box, .highlight:
                let r = resized(m.rect)
                m.from = EditPoint(x: r.x, y: r.y)
                m.to = EditPoint(x: r.x + r.w, y: r.y + r.h)
            case .text:
                break
            }
            edits.marks[i] = m
        case .blur(let i) where edits.blurs.indices.contains(i):
            edits.blurs[i] = resized(edits.blurs[i])
        case .crop:
            if let crop = edits.crop { edits.crop = resized(crop) }
        default:
            e.selected = nil
        }
        if edits != before, !e.nudging {
            e.history.append(before)
            e.nudging = true
        }
        editor = e
    }

    /// ⌫: deletes the selected item; with nothing selected, clears everything. Undo brings it back.
    mutating func deleteSelected() {
        guard var e = editor else { return }
        guard let selection = e.selected else {
            clearEdits()
            return
        }
        e.history.append(edits)
        e.selected = nil
        e.nudging = false
        switch selection {
        case .mark(let i) where edits.marks.indices.contains(i): edits.marks.remove(at: i)
        case .blur(let i) where edits.blurs.indices.contains(i): edits.blurs.remove(at: i)
        case .crop: edits.crop = nil
        default: e.history.removeLast()   // nothing there
        }
        editor = e
    }

    /// The area an item covers (an arrow's two ends; text measured roughly: about 0.6 of its size per
    /// character), for its selection frame and for clicking on it. `aspect` is the image's width
    /// divided by its height.
    func bounds(of selection: EditSelection, aspect: Double) -> EditRect? {
        switch selection {
        case .mark(let i):
            guard edits.marks.indices.contains(i) else { return nil }
            let m = edits.marks[i]
            if m.kind == .text {
                // Text is 2.2% of the image's longest side.
                let size = 0.022, a = max(aspect, 0.0001)
                let lines = m.text.split(separator: "\n", omittingEmptySubsequences: false)
                let longest = Double(lines.map(\.count).max() ?? 1)
                let w = max(longest, 1) * 0.6 * size * max(1, 1 / a)
                let h = Double(max(lines.count, 1)) * 1.25 * size * max(a, 1)
                return EditRect(x: m.from.x, y: m.from.y, w: w, h: h)
            }
            return m.rect
        case .blur(let i):
            return edits.blurs.indices.contains(i) ? edits.blurs[i] : nil
        case .crop:
            return edits.crop
        }
    }

    private func isText(_ selection: EditSelection) -> Bool {
        if case .mark(let i) = selection, edits.marks.indices.contains(i) { return edits.marks[i].kind == .text }
        return false
    }

    /// The item under a point (the one drawn last first), for clicking to select it. Boxes, blurs
    /// and the crop are picked by their edges, so clicking inside a big one still reaches what's in it.
    func item(at p: EditPoint, aspect: Double) -> EditSelection? {
        let near = 0.02
        func onEdge(_ r: EditRect) -> Bool {
            let inside = p.x >= r.x - near && p.x <= r.x + r.w + near && p.y >= r.y - near && p.y <= r.y + r.h + near
            let deep = p.x > r.x + near && p.x < r.x + r.w - near && p.y > r.y + near && p.y < r.y + r.h - near
            return inside && !deep
        }
        func within(_ r: EditRect) -> Bool {
            p.x >= r.x - near && p.x <= r.x + r.w + near && p.y >= r.y - near && p.y <= r.y + r.h + near
        }
        for i in edits.marks.indices.reversed() {
            let m = edits.marks[i]
            switch m.kind {
            case .arrow:
                let dx = m.to.x - m.from.x, dy = m.to.y - m.from.y
                let t = max(0, min(1, ((p.x - m.from.x) * dx + (p.y - m.from.y) * dy) / max(dx * dx + dy * dy, 1e-9)))
                if p.distance(to: EditPoint(x: m.from.x + t * dx, y: m.from.y + t * dy)) <= near { return .mark(i) }
            case .box:
                if onEdge(m.rect) { return .mark(i) }
            case .highlight:
                if within(m.rect) { return .mark(i) }
            case .text:
                if let r = bounds(of: .mark(i), aspect: aspect), within(r) { return .mark(i) }
            }
        }
        for i in edits.blurs.indices.reversed() where within(edits.blurs[i]) { return .blur(i) }
        if let crop = edits.crop, onEdge(crop) { return .crop }
        return nil
    }

    /// Clear: no marks, blurs or crop (Undo brings them back).
    mutating func clearEdits() {
        finishTyping(keep: true)
        guard !edits.isEmpty else { return }
        editor?.history.append(edits)
        editor?.selected = nil
        editor?.nudging = false
        edits = ImageEdits()
    }

    /// Done keeps the edits; Esc puts back what there was before the editor opened.
    mutating func endEditing(keep: Bool) {
        finishTyping(keep: true)
        guard let e = editor else { return }
        if !keep { edits = e.before }
        editor = nil
    }

    // MARK: Keyboard

    enum Arrow { case left, right, up, down }

    /// The controls Tab moves through, as the box shows them now.
    var fields: [ExportField] {
        var fields: [ExportField] = [.name]
        if formats.count > 1 { fields.append(.format) }
        if showsImageOptions { fields.append(.size) }
        if showsImageOptions && format.isLossy { fields.append(.quality) }
        if canEdit { fields.append(.markup) }
        return fields
    }

    /// Tab (or ⇧Tab) from `field`, wrapping around.
    func field(after field: ExportField, backward: Bool = false) -> ExportField {
        let all = fields
        guard let i = all.firstIndex(of: field) else { return .name }
        return all[(i + (backward ? -1 : 1) + all.count) % all.count]
    }

    /// An arrow key on a control. Format: → ↓ next, ← ↑ previous (menu order). Size: → ↓ smaller,
    /// ← ↑ bigger (the buttons' order). Quality: → ↑ higher, ← ↓ lower. Stops at the ends.
    mutating func change(_ field: ExportField, _ arrow: Arrow) {
        func step<T: Equatable>(_ list: [T], _ current: T, _ delta: Int) -> T {
            guard let i = list.firstIndex(of: current) else { return list.first ?? current }
            return list[min(max(i + delta, 0), list.count - 1)]
        }
        let forward = arrow == .right || arrow == .down
        switch field {
        case .name, .markup:
            break
        case .format:
            format = step(formats, format, forward ? 1 : -1)
        case .size:
            scale = step(Self.scales, scale, forward ? 1 : -1)
        case .quality:
            let higher = arrow == .right || arrow == .up
            quality = step(Self.qualities, quality, higher ? -1 : 1)   // the list runs from best to smallest
        }
    }

    var fileNames: [String] {
        ExportNaming.names(typed: name, originals: originals,
                           extensions: convertible.map { $0 ? outputFormat.fileExtension : nil },
                           keepTypedExtension: format == .txt)
    }

    /// The format files are written in: an edited image whose format is kept becomes a PNG.
    var outputFormat: ExportFormat { format == .original && !edits.isEmpty ? .png : format }

    /// A single image (a card, or one image file) can be blurred and cropped.
    var canEdit: Bool { source != .text && originals.count == 1 && convertible.first == true }

    /// Quality and size apply: an image is being re-encoded.
    var showsImageOptions: Bool { format.isImage && convertible.contains(true) }

    /// "Beach.jpg", or "Trip 1.jpg, Trip 2.jpg and 3 more".
    var namesSummary: String {
        let names = fileNames
        guard names.count > 2 else { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
    }
}
