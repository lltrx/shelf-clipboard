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
enum ExportField: Equatable { case name, format, size, quality }

/// The image editor's tools: Blur pixelates the area dragged over, Crop keeps only it.
enum EditTool: Equatable { case blur, crop }

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

    var isEmpty: Bool { blurs.isEmpty && crop == nil }

    /// Smaller than this (a click, or a slip of the mouse) isn't an area.
    static let smallest = 0.01

    /// "2 areas hidden, cropped"
    var summary: String {
        var parts: [String] = []
        if !blurs.isEmpty { parts.append(blurs.count == 1 ? "1 area hidden" : "\(blurs.count) areas hidden") }
        if crop != nil { parts.append("cropped") }
        return parts.joined(separator: ", ")
    }
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
        var tool: EditTool = .blur
        var before: ImageEdits
        var history: [ImageEdits] = []
        var canUndo: Bool { !history.isEmpty }
    }

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

    /// An area dragged out with the current tool: Blur adds one, Crop replaces the crop.
    mutating func addEdit(_ rect: EditRect) {
        guard var e = editor, let area = rect.clamped,
              area.w >= ImageEdits.smallest, area.h >= ImageEdits.smallest else { return }
        e.history.append(edits)
        switch e.tool {
        case .blur: edits.blurs.append(area)
        case .crop: edits.crop = area
        }
        editor = e
    }

    mutating func undoEdit() {
        guard let previous = editor?.history.popLast() else { return }
        edits = previous
    }

    /// Clear: no blurs and no crop (Undo brings them back).
    mutating func clearEdits() {
        guard !edits.isEmpty else { return }
        editor?.history.append(edits)
        edits = ImageEdits()
    }

    /// Done keeps the edits; Esc puts back what there was before the editor opened.
    mutating func endEditing(keep: Bool) {
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
        case .name:
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
