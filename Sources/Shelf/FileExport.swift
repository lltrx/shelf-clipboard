import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// The paste box's files: made from a card, with the name, format, size and edits chosen in the box.
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
        var edits = ImageEdits()
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
            try convertImage(at: source, to: job.format, quality: job.quality, scale: job.scale, edits: job.edits).write(to: url)
            return [url]
        case .files(let sources):
            var out: [URL] = []
            for (i, source) in sources.enumerated() where i < job.names.count {
                guard fm.fileExists(atPath: source.path) else {
                    throw failure("“\(source.lastPathComponent)” is no longer in \(source.deletingLastPathComponent().path).")
                }
                let url = dir.appendingPathComponent(job.names[i])
                // Same format at full size is just a rename: copy, don't re-encode (and lose quality).
                let sameFormat = ExportFormat.of(extension: source.pathExtension) == job.format && job.scale == 1 && job.edits.isEmpty
                if job.format != .original, i < job.convert.count, job.convert[i], !sameFormat {
                    try convertImage(at: source, to: job.format, quality: job.quality, scale: job.scale, edits: job.edits).write(to: url)
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
    /// size on the page when it's scaled down. Blurred areas are hidden and the crop applied first.
    static func convertImage(at url: URL, to format: ExportFormat, quality: Double, scale: Double,
                             edits: ImageEdits = ImageEdits()) throws -> Data {
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
        if !edits.isEmpty {
            guard let edited = apply(edits, to: image) else { throw failure("Couldn't blur or crop the image.") }
            image = edited
        }
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

    /// The image with each blurred area turned into big blocks of its own average colors (a
    /// mosaic: the original pixels can't be recovered from it, unlike a light blur), the marks
    /// drawn on it, then cropped. Everything is in fractions of the image, so the editor's small
    /// preview and the full-size file match.
    static func apply(_ edits: ImageEdits, to image: CGImage) -> CGImage? {
        var out = image
        let width = image.width, height = image.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if !edits.blurs.isEmpty || !edits.marks.isEmpty {
            let rgb = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            guard let space = rgb ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = bitmap(width, height, space), let data = context.data else { return nil }
            context.draw(image, in: bounds)
            let pixels = data.assumingMemoryBound(to: UInt8.self)   // RGBA rows, the top one first
            let rowBytes = context.bytesPerRow
            let longest = Double(max(width, height))
            for blur in edits.blurs {
                guard let area = blur.clamped else { continue }
                let x0 = Int((area.x * Double(width)).rounded(.down)), x1 = min(width, Int(((area.x + area.w) * Double(width)).rounded(.up)))
                let y0 = Int((area.y * Double(height)).rounded(.down)), y1 = min(height, Int(((area.y + area.h) * Double(height)).rounded(.up)))
                guard x1 > x0, y1 > y0 else { continue }
                // Blocks a third of the area's short side (a line of text becomes one or two rows of
                // them), but never smaller than 1% of the image, nor bigger than 4%.
                let short = Double(min(x1 - x0, y1 - y0))
                let block = max(1, Int(min(max(short / 3, longest / 100, 2), longest / 25).rounded()))
                for by in stride(from: y0, to: y1, by: block) {
                    for bx in stride(from: x0, to: x1, by: block) {
                        let ex = min(bx + block, x1), ey = min(by + block, y1)
                        var sum = (0, 0, 0, 0)
                        for y in by..<ey {
                            var i = y * rowBytes + bx * 4
                            for _ in bx..<ex {
                                sum.0 += Int(pixels[i]); sum.1 += Int(pixels[i + 1])
                                sum.2 += Int(pixels[i + 2]); sum.3 += Int(pixels[i + 3])
                                i += 4
                            }
                        }
                        let count = (ex - bx) * (ey - by)
                        let average = [sum.0, sum.1, sum.2, sum.3].map { UInt8(($0 + count / 2) / count) }
                        for y in by..<ey {
                            var i = y * rowBytes + bx * 4
                            for _ in bx..<ex {
                                pixels[i] = average[0]; pixels[i + 1] = average[1]
                                pixels[i + 2] = average[2]; pixels[i + 3] = average[3]
                                i += 4
                            }
                        }
                    }
                }
            }
            draw(edits.marks, in: context, width: Double(width), height: Double(height))
            guard let made = context.makeImage() else { return nil }
            out = made
        }
        if let crop = edits.crop?.clamped {
            // Like the blurs, measured from the top left (as CGImage cropping is).
            let rect = CGRect(x: crop.x * Double(width), y: crop.y * Double(height),
                              width: crop.w * Double(width), height: crop.h * Double(height)).integral.intersection(bounds)
            guard rect.width >= 1, rect.height >= 1, let cropped = out.cropping(to: rect) else { return nil }
            out = cropped
        }
        return out
    }

    /// Arrows, boxes, highlights and text, sized to the image (lines about 0.35% of its longest
    /// side, text 2.2%), so they look the same in the preview and the file.
    private static func draw(_ marks: [ImageMark], in context: CGContext, width: Double, height: Double) {
        guard !marks.isEmpty else { return }
        let longest = max(width, height)
        let line = CGFloat(max(2, longest * 0.0035))
        func color(_ c: MarkColor, alpha: Double = 1) -> CGColor {
            CGColor(srgbRed: CGFloat(c.rgb.red), green: CGFloat(c.rgb.green), blue: CGFloat(c.rgb.blue), alpha: CGFloat(alpha))
        }
        // The context's y runs up from the bottom; marks are measured down from the top.
        func point(_ p: EditPoint) -> CGPoint { CGPoint(x: CGFloat(p.x * width), y: CGFloat(height - p.y * height)) }
        let shadow = CGColor(gray: 0, alpha: 0.35)

        for mark in marks {
            context.saveGState()
            let a = point(mark.from), b = point(mark.to)
            let area = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            switch mark.kind {
            case .highlight:
                context.setBlendMode(.multiply)   // like a marker: dark text stays dark
                context.setFillColor(color(mark.color, alpha: 0.45))
                context.fill(area)
            case .box:
                context.setShadow(offset: .zero, blur: line, color: shadow)
                context.setStrokeColor(color(mark.color))
                context.setLineWidth(line)
                context.setLineJoin(.round)
                let r = min(line * 1.5, min(area.width, area.height) / 2)
                context.addPath(CGPath(roundedRect: area, cornerWidth: r, cornerHeight: r, transform: nil))
                context.strokePath()
            case .arrow:
                context.setShadow(offset: .zero, blur: line, color: shadow)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head: CGFloat = line * 4.5
                let spread: CGFloat = 0.45
                let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
                let shaftEnd = length > head
                    ? CGPoint(x: b.x - cos(angle) * head * 0.7, y: b.y - sin(angle) * head * 0.7)
                    : a
                context.setStrokeColor(color(mark.color))
                context.setLineWidth(line)
                context.setLineCap(.round)
                context.move(to: a)
                context.addLine(to: shaftEnd)
                context.strokePath()
                context.setFillColor(color(mark.color))
                context.move(to: b)
                context.addLine(to: CGPoint(x: b.x - cos(angle - spread) * head, y: b.y - sin(angle - spread) * head))
                context.addLine(to: CGPoint(x: b.x - cos(angle + spread) * head, y: b.y - sin(angle + spread) * head))
                context.closePath()
                context.fillPath()
            case .text:
                drawText(mark.text, topLeft: a, size: max(14, longest * 0.022), color: color(mark.color),
                         outline: mark.color.isLight ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1),
                         maxWidth: max(width - Double(a.x), longest * 0.05), in: context)
            }
            context.restoreGState()
        }
    }

    /// Bold text with an outline, its top left at `topLeft` (Core Text, so Arabic and other
    /// scripts lay out right).
    private static func drawText(_ text: String, topLeft: CGPoint, size: Double, color: CGColor, outline: CGColor,
                                 maxWidth: Double, in context: CGContext) {
        guard !text.isEmpty else { return }
        let points = CGFloat(size)
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, points, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, points, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): outline,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -5.0,   // fill, plus an outline 5% of the size
        ]
        let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: CGFloat(maxWidth), height: CGFloat.greatestFiniteMagnitude), nil)
        let box = CGRect(x: topLeft.x, y: topLeft.y - fit.height.rounded(.up), width: fit.width.rounded(.up) + 2,
                         height: fit.height.rounded(.up) + 1)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
    }

    /// An 8-bit RGBA canvas, in the image's color space if it can have one (else sRGB).
    private static func bitmap(_ width: Int, _ height: Int, _ space: CGColorSpace) -> CGContext? {
        func make(_ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        return make(space) ?? CGColorSpace(name: CGColorSpace.sRGB).flatMap(make)
    }

    /// The image file at `url`, its orientation applied, at most `maxPixels` on its longest side:
    /// what the editor shows.
    static func displayImage(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
    static func describe(_ url: URL, format: ExportFormat, quality: Double, scale: Double, convert: Bool,
                         edits: ImageEdits = ImageEdits()) -> String {
        if !convert || format == .original {
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            let size = isImage(url.path) ? pixelSize(url).map { "\($0.width) × \($0.height)" } : nil
            return [size, bytes.map(byteCount)].compactMap { $0 }.joined(separator: " · ")
        }
        guard let data = try? convertImage(at: url, to: format, quality: quality, scale: scale, edits: edits) else { return "" }
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
