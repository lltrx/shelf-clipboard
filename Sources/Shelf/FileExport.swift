import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Copy as File: makes real files from a card, with the name and format chosen in the form.
/// They are written to Application Support/Shelf/Exports (mode 700) and deleted after a day;
/// pasting or dropping them into another app (Finder, Mail, Slack…) makes that app's own copy.
enum FileExport {
    /// What to write. Text is turned into bytes beforehand, on the main thread (AppKit's
    /// rich text conversion wants that); images and files are handled off the main thread.
    struct Job {
        enum Content {
            case data(Data)
            case image(URL)
            case files([URL])
        }

        var content: Content
        var names: [String]
        var format: ExportFormat
        var quality: Double
        var scale: Double
        var convert: [Bool]   // for files: re-encode this one (an image) in `format`
    }

    /// Image formats this Mac can write. HEIC needs a hardware encoder that some Intel Macs lack.
    static let writableImageFormats: [ExportFormat] = {
        let types = Set((CGImageDestinationCopyTypeIdentifiers() as NSArray) as? [String] ?? [])
        return ExportFormat.image.filter { $0 == .pdf || types.contains($0.utType.identifier) }
    }()

    private static let readableImageTypes = Set((CGImageSourceCopyTypeIdentifiers() as NSArray) as? [String] ?? [])

    /// An image file Shelf can convert: PNG, JPEG, HEIC, TIFF, GIF, WebP, camera RAW…
    static func isImage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext), type.conforms(to: .image) else { return false }
        return readableImageTypes.contains(type.identifier)
    }

    static func write(_ job: Job, in root: URL) throws -> [URL] {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        switch job.content {
        case .data(let data):
            let url = dir.appendingPathComponent(job.names[0])
            try data.write(to: url)
            return [url]
        case .image(let source):
            let url = dir.appendingPathComponent(job.names[0])
            try convertImage(at: source, to: job.format, quality: job.quality, scale: job.scale).write(to: url)
            return [url]
        case .files(let sources):
            var out: [URL] = []
            for (i, source) in sources.enumerated() where i < job.names.count {
                guard fm.fileExists(atPath: source.path) else {
                    throw failure("“\(source.lastPathComponent)” is no longer in \(source.deletingLastPathComponent().path).")
                }
                let url = dir.appendingPathComponent(job.names[i])
                if job.format != .original, i < job.convert.count, job.convert[i] {
                    try convertImage(at: source, to: job.format, quality: job.quality, scale: job.scale).write(to: url)
                } else {
                    try fm.copyItem(at: source, to: url)   // a clone on APFS: instant, no extra space
                }
                out.append(url)
            }
            return out
        }
    }

    /// The image file `url`, re-encoded. Orientation is applied; other metadata, such as where a
    /// photo was taken, is left out. The resolution (dpi) is adjusted so the image keeps its
    /// size on the page when it's scaled down.
    static func convertImage(at url: URL, to format: ExportFormat, quality: Double, scale: Double) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw failure("Shelf can't read “\(url.lastPathComponent)” as an image.") }

        let longest = max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(longest) * scale).rounded())),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw failure("Shelf can't read “\(url.lastPathComponent)” as an image.")
        }
        let factor = Double(max(image.width, image.height)) / Double(longest)
        let dpiX = (properties[kCGImagePropertyDPIWidth] as? Double).map { $0 * factor }
        let dpiY = (properties[kCGImagePropertyDPIHeight] as? Double).map { $0 * factor }

        if format == .pdf {
            guard let pdf = pdfPage(image, dpiX: dpiX ?? 72, dpiY: dpiY ?? dpiX ?? 72) else { throw failure("Couldn't make the PDF.") }
            return pdf
        }
        if format == .jpeg, let flat = flattened(image) { image = flat }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.utType.identifier as CFString, 1, nil) else {
            throw failure("This Mac can't save \(format.title) images.")
        }
        var out: [CFString: Any] = [:]
        if format.isLossy { out[kCGImageDestinationLossyCompressionQuality] = quality }
        if let dpiX { out[kCGImagePropertyDPIWidth] = dpiX }
        if let dpiY { out[kCGImagePropertyDPIHeight] = dpiY }
        CGImageDestinationAddImage(destination, image, out as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw failure("Couldn't save the \(format.title) image.") }
        return data as Data
    }

    /// One PDF page the size of the image (at its resolution).
    private static func pdfPage(_ image: CGImage, dpiX: Double, dpiY: Double) -> Data? {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / max(dpiX, 1), height: Double(image.height) * 72 / max(dpiY, 1))
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// JPEG has no transparency, so clear areas (like a window screenshot's shadow) would turn
    /// black. Put the image on white instead.
    private static func flattened(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        let rgb = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let space = rgb ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// "1440 × 900 · 312 KB" for the form: what the file will be, measured by actually making it.
    /// Runs off the main thread.
    static func describe(_ url: URL, format: ExportFormat, quality: Double, scale: Double, convert: Bool) -> String {
        if !convert || format == .original {
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            let size = isImage(url.path) ? pixelSize(url).map { "\($0.width) × \($0.height)" } : nil
            return [size, bytes.map(byteCount)].compactMap { $0 }.joined(separator: " · ")
        }
        guard let data = try? convertImage(at: url, to: format, quality: quality, scale: scale) else { return "" }
        let size = format == .pdf ? nil : pixelSize(data).map { "\($0.width) × \($0.height)" }
        return [size, byteCount(Int64(data.count))].compactMap { $0 }.joined(separator: " · ")
    }

    private static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(of: source)
    }

    private static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(of: source)
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var w = p[kCGImagePropertyPixelWidth] as? Int, var h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        if let orientation = p[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&w, &h) }   // rotated 90°
        return (w, h)
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Deletes exports more than a day old. Runs at launch and hourly.
    static func prune(_ root: URL, olderThan age: TimeInterval = 86400) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for dir in dirs {
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if Date().timeIntervalSince(created) > age { try? fm.removeItem(at: dir) }
        }
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "Shelf", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

extension ExportFormat {
    var utType: UTType {
        switch self {
        case .original: return .data
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif: return .gif
        case .pdf: return .pdf
        case .txt: return .plainText
        case .md: return UTType(filenameExtension: "md") ?? .plainText
        case .rtf: return .rtf
        case .docx: return UTType(filenameExtension: "docx") ?? .data
        case .html: return .html
        }
    }
}
