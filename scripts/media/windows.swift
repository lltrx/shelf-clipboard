// Where windows are, in the coordinates screencapture and mouse.swift use: points, with the origin at
// the top left of the main screen.
//
//   windows [App]    an app's on-screen windows (default Shelf): id, x,y,w,h, layer, alpha, title
//   windows --screen the main screen's frame and visible frame (without the menu bar and the Dock)
//
// The id goes to `screencapture -l<id>`, the rectangle to `screencapture -R<x,y,w,h>`. Shelf's windows:
// the shelf (full width, about 312 tall, at the bottom), the paste box above it, the preview, the
// Settings window, the small message at the bottom (Grab Text), and the menu bar icon (tiny, layer 25).
import AppKit
import CoreGraphics

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--screen" {
    let main = CGMainDisplayID()
    let bounds = CGDisplayBounds(main)
    print("frame\t\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))")
    if let screen = NSScreen.screens.first {
        let height = screen.frame.height
        let v = screen.visibleFrame
        print("visible\t\(Int(v.minX)),\(Int(height - v.maxY)),\(Int(v.width)),\(Int(v.height))")
        print("scale\t\(screen.backingScaleFactor)")
    }
    exit(0)
}

let owner = args.first ?? "Shelf"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var found = false
for window in info where (window[kCGWindowOwnerName as String] as? String) == owner {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let dict = window[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
    let title = window[kCGWindowName as String] as? String ?? ""
    print("\(id)\t\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))\tlayer \(layer)\talpha \(alpha)\t\(title)")
    found = true
}
if !found {
    FileHandle.standardError.write("No on-screen windows for \(owner). (Titles need Screen Recording permission for this terminal.)\n".data(using: .utf8)!)
}
