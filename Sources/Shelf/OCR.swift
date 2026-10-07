import CoreGraphics
import ImageIO
import Vision

/// On-device text recognition (Apple Vision) so screenshots are searchable. Nothing leaves the Mac.
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
}
