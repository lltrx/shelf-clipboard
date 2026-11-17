import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device text recognition (Apple Vision): screenshots are searchable, and Grab Text from Screen
/// reads any part of the screen. Nothing leaves the Mac.
enum OCR {
    static func recognize(_ url: URL) -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        if let supported = try? request.supportedRecognitionLanguages() {
            let wanted = ["en-US", "ar-SA"].filter(supported.contains)
            if !wanted.isEmpty { request.recognitionLanguages = wanted }
        }
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Grab Text from Screen: runs the system's screenshot tool to choose an area (saved to `file`,
    /// then deleted) and reads the text in it. Nil when cancelled. Blocks, so call it off the main thread.
    static func grabFromScreen(_ file: URL) -> String? {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-i", "-x", "-t", "png", file.path]   // -i: choose an area, -x: no sound
        guard (try? capture.run()) != nil else { return nil }
        capture.waitUntilExit()
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }   // Esc
        defer { try? FileManager.default.removeItem(at: file) }
        return recognize(file)
    }
}
