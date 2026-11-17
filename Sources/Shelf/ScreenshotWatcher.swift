import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Adds screenshots to the shelf. macOS saves screenshots (⇧⌘3, ⇧⌘4, ⇧⌘5) as files, on the Desktop
/// unless changed in the Screenshot app's Options, so they never reach the clipboard. This watches
/// that folder and reports each new file macOS marks as a screen capture (the
/// `com.apple.metadata:kMDItemIsScreenCapture` attribute), not other images saved there.
final class ScreenshotWatcher {
    var onScreenshot: (URL) -> Void = { _ in }

    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var known: Set<String> = []
    private var pending: DispatchWorkItem?

    /// The folder macOS saves screenshots to.
    static var screenshotFolder: URL {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let path = custom.map { ($0 as NSString).expandingTildeInPath } ?? (NSHomeDirectory() + "/Desktop")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Starts watching, or follows the screenshot folder if it has changed. Cheap to call again.
    func start() {
        let folder = Self.screenshotFolder
        guard source == nil || folder != self.folder else { return }
        stop()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.folder = folder
        known = Set(names(in: folder))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        folder = nil
    }

    /// Something in the folder changed. Wait a moment so a screenshot being saved is complete.
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func scan() {
        guard let folder else { return }
        let names = Set(names(in: folder))
        let added = names.subtracting(known)
        known = names
        for name in added.sorted() {
            let url = folder.appendingPathComponent(name)
            if Self.isScreenshot(url) { onScreenshot(url) }
        }
    }

    private func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    /// macOS marks every screenshot file with this attribute (it's what Spotlight's
    /// kMDItemIsScreenCapture reads).
    static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// The screenshot as an image card, as if it had been copied. Stored as PNG, like every image
    /// card, so other formats (if Screenshot is set to save JPEG or HEIC) are converted. Runs off
    /// the main thread.
    static func capture(_ url: URL) -> Capture? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var png = data
        if (CGImageSourceGetType(source) as String?) != UTType.png.identifier {
            let out = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            png = out as Data
        }
        return Capture(kind: .image, imageData: png, detail: "\(image.width) × \(image.height)",
                       hash: Monitor.digest("image", png),
                       sourceBundle: screenshotApp, sourceName: "Screenshot")
    }

    /// The Screenshot app, so screenshot cards show its icon (and it can be ignored like any app).
    static let screenshotApp = "com.apple.screenshot.launcher"
}
