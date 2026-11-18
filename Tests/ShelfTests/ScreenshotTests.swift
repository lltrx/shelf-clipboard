import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Shelf

final class ScreenshotTests: XCTestCase {
    /// A 4 × 3 image file in a temporary folder.
    private func imageFile(_ type: UTType, _ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shot-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testScreenshotBecomesAnImageCard() throws {
        let url = try imageFile(.png, "png")
        let capture = try XCTUnwrap(ScreenshotWatcher.capture(url))
        XCTAssertEqual(capture.kind, .image)
        XCTAssertEqual(capture.detail, "4 × 3")
        XCTAssertEqual(capture.imageData, try Data(contentsOf: url))   // a PNG is kept as it is
        XCTAssertEqual(capture.sourceName, "Screenshot")
        XCTAssertEqual(capture.sourceBundle, ScreenshotWatcher.screenshotApp)
    }

    func testOtherFormatsAreStoredAsPNG() throws {
        let url = try imageFile(.jpeg, "jpg")
        let capture = try XCTUnwrap(ScreenshotWatcher.capture(url))
        XCTAssertEqual(capture.imageData?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))   // PNG signature
    }

    func testNotAnImage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).txt")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)
        XCTAssertNil(ScreenshotWatcher.capture(url))
    }

    func testOnlyFilesMacOSMarksAsScreenshotsCount() throws {
        let url = try imageFile(.png, "png")
        XCTAssertFalse(ScreenshotWatcher.isScreenshot(url))   // an ordinary image saved there

        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = marker.withUnsafeBytes { bytes in
            setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", bytes.baseAddress, bytes.count, 0, 0)
        }
        XCTAssertEqual(result, 0)
        XCTAssertTrue(ScreenshotWatcher.isScreenshot(url))
    }
}
