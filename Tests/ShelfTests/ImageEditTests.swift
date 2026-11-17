import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Shelf

/// Blur and crop, on real images (Core Graphics, so macOS only).
final class ImageEditTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private func canvas(_ width: Int, _ height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    /// Red on top, blue below.
    private func twoColors(_ width: Int = 100, _ height: Int = 50) throws -> CGImage {
        let c = try canvas(width, height)
        c.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))          // the context's y runs up
        c.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        c.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return try XCTUnwrap(c.makeImage())
    }

    /// Black and white pixels, alternating.
    private func checkerboard(_ size: Int) throws -> CGImage {
        let c = try canvas(size, size)
        c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        c.fill(CGRect(x: 0, y: 0, width: size, height: size))
        c.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        for y in 0..<size { for x in 0..<size where (x + y) % 2 == 0 { c.fill(CGRect(x: x, y: y, width: 1, height: 1)) } }
        return try XCTUnwrap(c.makeImage())
    }

    /// (red, green, blue) at x, y counted from the top left.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> (Int, Int, Int) {
        let c = try canvas(image.width, image.height)
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(c.data).assumingMemoryBound(to: UInt8.self)
        let i = y * c.bytesPerRow + x * 4   // the buffer's first row is the top one
        return withExtendedLifetime(c) { (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])) }
    }

    func testCropKeepsTheAreaMeasuredFromTheTop() throws {
        let image = try twoColors()
        let top = try XCTUnwrap(FileExport.apply(ImageEdits(crop: EditRect(x: 0.5, y: 0, w: 0.5, h: 0.5)), to: image))
        XCTAssertEqual(top.width, 50)
        XCTAssertEqual(top.height, 25)
        XCTAssertEqual(try pixel(top, 10, 10).0, 255)    // red
        let bottom = try XCTUnwrap(FileExport.apply(ImageEdits(crop: EditRect(x: 0, y: 0.5, w: 1, h: 0.5)), to: image))
        XCTAssertEqual(try pixel(bottom, 10, 10).2, 255) // blue
    }

    func testBlurTurnsTheAreaIntoBlocksAndLeavesTheRest() throws {
        let image = try checkerboard(60)
        let edited = try XCTUnwrap(FileExport.apply(ImageEdits(blurs: [EditRect(x: 0, y: 0, w: 0.5, h: 0.5)]), to: image))
        XCTAssertEqual(edited.width, 60)
        // Inside: neighbouring pixels are the same grey block, not black and white any more.
        let a = try pixel(edited, 4, 4), b = try pixel(edited, 5, 4)
        XCTAssertEqual(a.0, b.0)
        XCTAssertTrue((40...215).contains(a.0), "\(a)")
        // Outside: untouched.
        let c = try pixel(edited, 40, 40), d = try pixel(edited, 41, 40)
        XCTAssertNotEqual(c.0, d.0)
    }

    func testEditedFileHasTheCroppedSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edit-\(UUID().uuidString).png")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try twoColors(200, 100), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let edits = ImageEdits(blurs: [EditRect(x: 0.1, y: 0.1, w: 0.3, h: 0.3)], crop: EditRect(x: 0, y: 0, w: 0.5, h: 1))
        let data = try FileExport.convertImage(at: url, to: .png, quality: 1, scale: 0.5, edits: edits)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let out = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(out.width, 50)    // half of 200, then half of that
        XCTAssertEqual(out.height, 50)
    }
}
