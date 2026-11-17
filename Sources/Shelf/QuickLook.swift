import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI

/// A file's own picture from Quick Look: a photo or screenshot, the first page of a PDF, the
/// start of a text file… Made off the main thread and cached. Shows the file's icon until it's
/// ready, and when there isn't one (a folder, a file that has been moved or deleted).
struct FileThumbnail: View {
    let path: String
    var maxSize: CGFloat = 200   // points
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 48, maxHeight: 48)
            }
        }
        .task(id: path) { await load() }
    }

    @MainActor private func load() async {
        let key = "\(path)#\(maxSize)" as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        guard FileManager.default.fileExists(atPath: path) else { return }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path),
                                                   size: CGSize(width: maxSize, height: maxSize),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
        let picture = thumbnail.nsImage
        Self.cache.setObject(picture, forKey: key)
        image = picture
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()
}

/// The full Quick Look preview of a file, the one Space shows in Finder: PDFs and text scroll,
/// images show whole, videos play.
struct QuickLookView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var preview: QLPreviewView?
        var url: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let made: QLPreviewView? = QLPreviewView(frame: .zero, style: .normal)
        if let preview = made {
            preview.autostarts = true
            preview.shouldCloseWithWindow = false
            preview.autoresizingMask = [.width, .height]
            container.addSubview(preview)
            context.coordinator.preview = preview
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let preview = context.coordinator.preview else { return }
        preview.frame = container.bounds
        if context.coordinator.url != url {
            context.coordinator.url = url
            preview.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.preview?.close()
    }
}
