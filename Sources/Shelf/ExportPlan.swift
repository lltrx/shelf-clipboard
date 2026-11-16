import Foundation

// Copy as File (⇧⌘C): what a card becomes as a file, and what that file is called.
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

/// The buttons of the Copy as File form: Return, ⌘C and ⌘S.
enum ExportAction { case paste, copy, save }

/// The Copy as File form: what is being made, and the choices so far.
struct ExportDraft: Equatable {
    enum Source: Equatable { case image, text, files }

    let item: ClipItem
    let source: Source
    let originals: [String]       // original file names; one made-up name for an image or text card
    let convertible: [Bool]       // for each original: whether the format choice applies to it
    let formats: [ExportFormat]   // choices in the Format menu
    var name: String
    var format: ExportFormat
    var quality = 0.85            // JPEG and HEIC
    var scale = 1.0               // images: 1, 0.75, 0.5 or 0.25 of the original size
    var busy = false
    var error: String?

    var fileNames: [String] {
        ExportNaming.names(typed: name, originals: originals,
                           extensions: convertible.map { $0 ? format.fileExtension : nil },
                           keepTypedExtension: format == .txt)
    }

    /// Quality and size apply: an image is being re-encoded.
    var showsImageOptions: Bool { format.isImage && convertible.contains(true) }

    /// "Beach.jpg", or "Trip 1.jpg, Trip 2.jpg and 3 more".
    var namesSummary: String {
        let names = fileNames
        guard names.count > 2 else { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
    }
}
