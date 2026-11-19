// Puts Shelf's demo content on the clipboard, one item at a time, with a pause after each so Shelf
// records it (it checks the clipboard every 0.4 s). Before each copy it brings a fitting app to the
// front (Notes, Safari, TextEdit, Terminal), because cards show the app a copy came from.
//
// The order is the README's: the last item copied is the first card in the shelf.
//
//   swiftc -O scripts/media/demo-content.swift -o /tmp/shelf-media-bin/demo-content   (demo.sh does this)
//   demo-content                 copy everything, in order
//   demo-content key image       copy only these, in this order
//   demo-content --list          the item names
//   demo-content --receipt FILE  only write the receipt image to FILE (PNG)
import AppKit

let pb = NSPasteboard.general

struct Item {
    let name: String
    let app: String?          // brought to the front first, so the card says it came from there
    let write: () -> Void
}

func plain(_ s: String) -> () -> Void {
    return {
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

/// The meeting notes as Notes puts them on the clipboard: plain text, RTF and HTML. The RTF is built
/// directly (no HTML import, which needs WebKit and failed now and then in a command-line tool).
func notes() -> () -> Void {
    return {
        let body = NSFont.systemFont(ofSize: 13), bold = NSFont.boldSystemFont(ofSize: 13)
        let text = NSMutableAttributedString()
        func add(_ s: String, _ font: NSFont, link: String? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let link, let url = URL(string: link) { attributes[.link] = url }
            text.append(NSAttributedString(string: s, attributes: attributes))
        }
        add("Launch notes\n", NSFont.boldSystemFont(ofSize: 16))
        add("Shelf 2.0", bold)
        add(" ships this week. Before then:\n", body)
        add("\u{2022}\tRecord the demo GIF\n", body)
        add("\u{2022}\tUpdate the ", body)
        add("README", body, link: "https://github.com/lltrx/shelf-clipboard")
        add("\n\u{2022}\tPost the release notes", body)
        let html = """
            <h3>Launch notes</h3><p><b>Shelf 2.0</b> ships this week. Before then:</p>
            <ul><li>Record the demo GIF</li><li>Update the <a href="https://github.com/lltrx/shelf-clipboard">README</a></li>
            <li>Post the release notes</li></ul>
            """
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text.string, forType: .string)
        if let rtf = try? text.data(from: NSRange(location: 0, length: text.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item.setData(rtf, forType: .rtf)
        }
        item.setString(html, forType: .html)
        pb.writeObjects([item])
    }
}

/// An order confirmation, 1800 × 1120: text Shelf can read (search "order" or "total"), a total to
/// point an arrow at, an email address to blur.
func receiptPNG() -> Data? {
    let width = 1800, height = 1120
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let cg = base.cgContext
    cg.translateBy(x: 0, y: CGFloat(height))   // y runs down from the top, like the web version
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    defer { NSGraphicsContext.restoreGraphicsState() }

    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    func draw(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, hex: UInt32, right: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: color(hex)]
        let text = s as NSString
        let w = right ? text.size(withAttributes: attributes).width : 0
        text.draw(at: CGPoint(x: x - w, y: y), withAttributes: attributes)
    }

    color(0xEEF1F6).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    color(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 80, y: 60, width: width - 160, height: height - 120), xRadius: 36, yRadius: 36).fill()
    color(0x2F6FEB).setFill()
    NSRect(x: 80, y: 60, width: width - 160, height: 20).fill()

    draw("Order confirmation", x: 160, y: 150, size: 80, weight: .bold, hex: 0x16181D)
    draw("Thanks for your order. Here are the details.", x: 160, y: 262, size: 46, weight: .regular, hex: 0x5B6270)
    let rows = [("Order", "#4821-7733"), ("Name", "Alex Morgan"), ("Email", "alex.morgan@example.com"), ("Ships", "Friday, 21 November")]
    for (i, row) in rows.enumerated() {
        let y = CGFloat(400 + i * 104)
        draw(row.0, x: 160, y: y, size: 46, weight: .medium, hex: 0x5B6270)
        draw(row.1, x: 520, y: y, size: 50, weight: .medium, hex: 0x16181D)
    }
    color(0xDFE2E8).setFill()
    NSRect(x: 160, y: 868, width: width - 320, height: 4).fill()
    draw("Total due", x: 160, y: 920, size: 64, weight: .bold, hex: 0x16181D)
    draw("$42.00", x: CGFloat(width - 160), y: 920, size: 64, weight: .bold, hex: 0x16181D, right: true)

    return rep.representation(using: .png, properties: [:])
}

func image() -> () -> Void {
    return {
        guard let png = receiptPNG() else {
            FileHandle.standardError.write("Couldn't draw the receipt.\n".data(using: .utf8)!)
            return
        }
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
    }
}

let items: [Item] = [
    Item(name: "list", app: "TextEdit", write: plain("Alex Morgan\nPriya Shah\nOmar Haddad\nLena Fischer")),
    Item(name: "json", app: "TextEdit",
         write: plain(#"{"app":"Shelf","version":"2.0.0","local":true,"features":["markup","grab text","snippets"]}"#)),
    Item(name: "arabic", app: "Notes", write: plain("مرحبًا بك في Shelf — كل ما تنسخه يبقى على جهازك")),
    Item(name: "code", app: "Terminal", write: plain("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}")),
    Item(name: "color", app: "TextEdit", write: plain("#2F6FEB")),
    Item(name: "link", app: "Safari",
         write: plain("https://github.com/lltrx/shelf-clipboard?utm_source=newsletter&utm_medium=email&fbclid=IwAR2demo")),
    Item(name: "key", app: "Terminal", write: plain("sk-ant-api03-DEMOkeyForScreenshotsOnly0042")),
    Item(name: "image", app: "Safari", write: image()),
    Item(name: "notes", app: "Notes", write: notes()),
    // Not in the default run: pinned to a "Replies" pinboard for the pinboard shot.
    Item(name: "snippet", app: "Notes", write: plain("Hi {{clipboard}}, thanks for your order. It ships on {{date}}.")),
]
let defaultOrder = ["list", "json", "arabic", "code", "color", "link", "key", "image", "notes"]

func bringToFront(_ app: String) {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", app]
    guard (try? open.run()) != nil else { return }
    open.waitUntilExit()
    Thread.sleep(forTimeInterval: 1.0)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--list" {
    print((defaultOrder + ["snippet"]).joined(separator: " "))
    exit(0)
}
if args.first == "--receipt" {
    guard args.count == 2, let png = receiptPNG(), (try? png.write(to: URL(fileURLWithPath: args[1]))) != nil else { exit(2) }
    print("wrote \(args[1])")
    exit(0)
}
let wanted = args.isEmpty ? defaultOrder : args
for name in wanted {
    guard let item = items.first(where: { $0.name == name }) else {
        FileHandle.standardError.write("Unknown item \(name). Items: \((defaultOrder + ["snippet"]).joined(separator: " "))\n".data(using: .utf8)!)
        exit(2)
    }
    if let app = item.app { bringToFront(app) }
    item.write()
    print("copied \(name)\(item.app.map { " from \($0)" } ?? "")")
    Thread.sleep(forTimeInterval: 1.5)
}
