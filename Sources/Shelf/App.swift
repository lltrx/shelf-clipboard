import AppKit
import ServiceManagement
import SwiftUI

/// Borderless panel that takes keyboard focus without activating Shelf,
/// so the app you were in stays frontmost and receives the paste.
final class ShelfPanel: NSPanel {
    var onResignKey: () -> Void = {}
    var allowsKey = true

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey()
    }

    /// Frosted, rounded content with a SwiftUI view inside.
    func host<V: View>(_ view: V) {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ShelfActions {
    private let retentionDays = 30
    private let panelHeight: CGFloat = 300
    /// Tags ⌘V events Shelf posts itself, so the paste stack does not count them as yours.
    private static let syntheticMarker: Int64 = 0x5348_4C46

    private var store: Store!
    private let monitor = Monitor()
    private let model = ShelfModel()
    private let panel = ShelfPanel()
    private let preview = ShelfPanel()
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var pruneTimer: Timer?

    private let ocrQueue = DispatchQueue(label: "shelf.ocr", qos: .utility)
    private var ocrRunning = false
    private var axPrompted = false

    // Paste stack in progress: each ⌘V you press pastes the next item.
    private var stackItems: [ClipItem] = []
    private var stackIndex = 0
    private var stackPlain = false
    private var stackMonitor: Any?
    private var stackActive: Bool { !stackItems.isEmpty }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try Store()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        model.actions = self

        setUpPanels()
        setUpStatusItem()

        let spec = UserDefaults.standard.string(forKey: "hotkey") ?? "cmd+shift+v"
        hotKey = HotKey(spec: spec) { [unowned self] in toggle() }

        monitor.onCapture = { [unowned self] capture in
            if stackActive { endStack() } // you copied something new; the stack is over
            store.upsert(capture)
            reload()
            if capture.kind == .image { runOCR() }
        }
        monitor.start()

        prune()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.prune() }
        runOCR()
    }

    // MARK: - Panels

    private func setUpPanels() {
        panel.host(ShelfView(model: model))
        preview.host(PreviewView(model: model))
        preview.allowsKey = false

        // Hide only when focus leaves both panels (moving into the editor is fine).
        let focusCheck = { [unowned self] in
            DispatchQueue.main.async { [self] in
                if !panel.isKeyWindow && !preview.isKeyWindow { hide() }
            }
        }
        panel.onResignKey = focusCheck
        preview.onResignKey = focusCheck
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [unowned self] _ in
            if model.editing { endEditing() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] event in
            if event.window === preview { return handleEditorKey(event) ? nil : event }
            guard event.window === panel else { return event }
            return handleKey(event) ? nil : event
        }
    }

    /// Returns true when the key was handled by the shelf instead of the search field.
    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)

        if model.naming != nil {                                         // typing a pinboard name
            if e.keyCode == 53 { model.naming = nil; model.pendingPin = nil; return true }
            return false
        }

        switch e.keyCode {
        case 53: model.previewing ? togglePreview() : hide(); return true   // esc
        case 123: model.move(cmd ? -1_000_000 : -1); return true            // ←
        case 124: model.move(cmd ? 1_000_000 : 1); return true              // →
        case 36, 76:                                                        // return (⇧ plain, ⌥ stack as one)
            if !model.stack.isEmpty {
                e.modifierFlags.contains(.option) ? pasteStackJoined() : startStack(plain: shift)
            } else {
                model.selected.map { paste($0, plain: shift) }
            }
            return true
        case 48: model.cycleTab(shift ? -1 : 1); return true                // tab
        case 49 where !cmd && model.query.isEmpty: togglePreview(); return true // space
        case 51 where cmd: model.selected.map(delete); return true          // ⌘⌫
        default: break
        }

        // Physical key codes, so shortcuts work with any keyboard layout (e.g. Arabic).
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1…9
        guard cmd else { return false }
        switch e.keyCode {
        case 35: requestPin(); return true                                  // P
        case 8 where model.query.isEmpty: model.selected.map(copy); return true // C
        case 45: model.startNaming(.new); return true                       // N
        case 1:                                                             // S: add to stack, move on
            if let item = model.selected { model.toggleStack(item); model.move(1) }
            return true
        case 14: model.selected.map(edit); return true                      // E
        case let k where digitKeys.contains(k):
            let list = model.filtered
            let i = digitKeys.firstIndex(of: k)!
            if list.indices.contains(i) { paste(list[i], plain: shift) }
            return true
        default: return false
        }
    }

    /// Keys while editing in the preview. Everything else goes to the text view.
    private func handleEditorKey(_ e: NSEvent) -> Bool {
        guard model.editing else { return false }
        switch e.keyCode {
        case 53: endEditing(); return true
        case 36, 76:
            guard e.modifierFlags.contains(.command) else { return false } // plain Return is a newline
            pasteEdited(plain: e.modifierFlags.contains(.shift))
            return true
        default: return false
        }
    }

    private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(x: frame.minX + 8, y: frame.minY + 8, width: frame.width - 16, height: panelHeight),
                       display: false)
        model.query = ""
        model.tab = nil
        model.selection = 0
        model.stack = []
        model.naming = nil
        model.now = Date()
        reload()
        panel.makeKeyAndOrderFront(nil)
        model.focusTick += 1
    }

    private func hide() {
        model.editing = false
        model.previewing = false
        model.naming = nil
        preview.allowsKey = false
        preview.orderOut(nil)
        panel.orderOut(nil)
    }

    private func reload() {
        model.items = store.all()
        model.boards = store.boards()
        if let tab = model.tab, !model.boards.contains(where: { $0.id == tab }) { model.tab = nil }
        let ids = Set(model.items.map(\.id))
        model.stack.removeAll { !ids.contains($0) }
        model.clampSelection()
    }

    // MARK: - Preview and editing

    func togglePreview() {
        model.previewing.toggle()
        guard model.previewing, let screen = panel.screen else {
            endEditing()
            preview.orderOut(nil)
            return
        }
        let vf = screen.visibleFrame
        let bottom = panel.frame.maxY + 12
        let width = min(920, vf.width * 0.7)
        let height = max(220, min(580, vf.maxY - bottom - 12))
        preview.setFrame(NSRect(x: vf.midX - width / 2, y: bottom, width: width, height: height), display: true)
        preview.orderFront(nil)
    }

    func edit(_ item: ClipItem) {
        guard item.editable else { return }
        if !model.previewing { togglePreview() }
        preview.allowsKey = true
        model.editing = true
        preview.makeKey()
    }

    private func endEditing() {
        guard model.editing else { return }
        model.editing = false
        preview.allowsKey = false
        if panel.isVisible { panel.makeKey() }
    }

    /// Saves the edited text as a new history item and pastes it.
    private func pasteEdited(plain: Bool) {
        guard let tv = model.editor, let original = model.selected else { return }
        let edited = tv.attributedString()
        let text = edited.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var formats: [(type: String, data: Data)] = []
        if original.formatted, let rtf = edited.rtf(from: NSRange(location: 0, length: edited.length), documentAttributes: [:]) {
            formats.append((NSPasteboard.PasteboardType.rtf.rawValue, rtf))
        }
        let capture = Capture(kind: Monitor.isLink(text) ? .link : .text, text: text,
                              hash: Monitor.digest("text", Data(text.utf8)),
                              sourceBundle: original.sourceBundle, sourceName: original.sourceName, formats: formats)
        guard let id = store.upsert(capture) else { return }
        reload()
        if let item = model.items.first(where: { $0.id == id }) { paste(item, plain: plain) }
    }

    func attributed(_ item: ClipItem) -> NSAttributedString {
        if item.formatted {
            let formats = Dictionary(store.formats(item.id).map { ($0.type, $0.data) }, uniquingKeysWith: { a, _ in a })
            if let d = formats["com.apple.flat-rtfd"], let a = NSAttributedString(rtfd: d, documentAttributes: nil) { return a }
            if let d = formats[NSPasteboard.PasteboardType.rtf.rawValue], let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a }
            if let d = formats[NSPasteboard.PasteboardType.html.rawValue], let a = NSAttributedString(html: d, documentAttributes: nil) { return a }
        }
        return NSAttributedString(string: item.text ?? "",
                                  attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    }

    // MARK: - Pinboards

    func imageURL(_ item: ClipItem) -> URL? { store.imageURL(item) }

    func setBoard(_ item: ClipItem, _ board: Int64?) {
        store.setBoard(item.id, board)
        reload()
    }

    /// ⌘P: unpin a pinned item; otherwise pin it, asking which board when there are several.
    private func requestPin() {
        guard let item = model.selected else { return }
        if item.pinned { setBoard(item, nil); return }
        if model.boards.isEmpty { model.pendingPin = item.id; model.startNaming(.new); return }
        if model.boards.count == 1 { setBoard(item, model.boards[0].id); return }

        let menu = NSMenu()
        for (i, board) in model.boards.enumerated() {
            let entry = NSMenuItem(title: board.name, action: #selector(pinFromMenu(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            entry.keyEquivalentModifierMask = []
            entry.tag = Int(board.id)
            entry.representedObject = NSNumber(value: item.id)
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let new = NSMenuItem(title: "New Pinboard…", action: #selector(newBoardFromMenu(_:)), keyEquivalent: "n")
        new.keyEquivalentModifierMask = []
        new.representedObject = NSNumber(value: item.id)
        new.target = self
        menu.addItem(new)
        let width = panel.frame.width
        menu.popUp(positioning: menu.items.first, at: NSPoint(x: width / 2 - 80, y: panelHeight - 44), in: panel.contentView)
    }

    @objc private func pinFromMenu(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.int64Value,
              let item = model.items.first(where: { $0.id == id }) else { return }
        setBoard(item, Int64(sender.tag))
    }

    @objc private func newBoardFromMenu(_ sender: NSMenuItem) {
        model.pendingPin = (sender.representedObject as? NSNumber)?.int64Value
        model.startNaming(.new)
    }

    func commitName() {
        let name = model.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { model.naming = nil; model.pendingPin = nil; reload() }
        guard !name.isEmpty, let naming = model.naming else { return }
        switch naming {
        case .new:
            let board = store.createBoard(name)
            if let pending = model.pendingPin { store.setBoard(pending, board) } else { model.tab = board }
        case .rename(let id):
            store.renameBoard(id, name)
        }
    }

    func deleteBoard(_ board: Board) {
        store.deleteBoard(board.id)
        reload()
    }

    // MARK: - Pasting

    /// Puts the item on the clipboard. Text keeps its stored RTF/HTML unless `plain` is set.
    private func write(_ item: ClipItem, plain: Bool = false, touch: Bool = true) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .link:
            let entry = NSPasteboardItem()
            entry.setString(item.text ?? "", forType: .string)
            if !plain {
                for f in store.formats(item.id) { entry.setData(f.data, forType: NSPasteboard.PasteboardType(f.type)) }
            }
            pb.writeObjects([entry])
        case .image:
            guard let url = store.imageURL(item), let png = try? Data(contentsOf: url) else { return }
            let entry = NSPasteboardItem()
            entry.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation { entry.setData(tiff, forType: .tiff) }
            pb.writeObjects([entry])
        case .file:
            pb.writeObjects(item.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
        }
        monitor.markOwnChange()
        if touch {
            store.touch(item.id)
            reload()
        }
    }

    func paste(_ item: ClipItem, plain: Bool) {
        write(item, plain: plain)
        hide()
        postPaste()
    }

    func copy(_ item: ClipItem) {
        write(item)
        hide()
    }

    func delete(_ item: ClipItem) {
        store.delete(item.id)
        reload()
    }

    /// Sends ⌘V to the frontmost app. Needs Accessibility; without it the item just stays on the clipboard.
    /// The system prompt is shown at most once per launch; after that, use "Allow Auto-Paste…" in the menu.
    private func postPaste() {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": !axPrompted] as CFDictionary) else {
            axPrompted = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down) // V
                e?.flags = .maskCommand
                e?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Paste stack

    /// Pastes the first stacked item now; each ⌘V you press afterwards pastes the next one.
    private func startStack(plain: Bool) {
        let items = model.stack.compactMap { id in model.items.first { $0.id == id } }
        guard let first = items.first else { return }
        hide()
        stackItems = items
        stackIndex = 0
        stackPlain = plain
        write(first, plain: plain, touch: false)
        postPaste()
        if stackMonitor == nil {
            stackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.stackKey(e) }
        }
        advanceStack(after: 0.3)
    }

    private func stackKey(_ e: NSEvent) {
        guard stackActive, e.keyCode == 9, e.modifierFlags.contains(.command),
              e.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return }
        advanceStack(after: 0.2)
    }

    /// Wait for the paste to land, then put the next item on the clipboard.
    private func advanceStack(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard stackActive else { return }
            stackIndex += 1
            if stackIndex < stackItems.count {
                write(stackItems[stackIndex], plain: stackPlain, touch: false)
            } else {
                endStack()
            }
            updateStatusIcon()
        }
    }

    private func endStack() {
        stackItems = []
        stackIndex = 0
        if let stackMonitor { NSEvent.removeMonitor(stackMonitor) }
        stackMonitor = nil
        updateStatusIcon()
    }

    /// ⌥Return: paste every stacked item at once, one per line.
    private func pasteStackJoined() {
        let texts = model.stack.compactMap { id in model.items.first { $0.id == id } }
            .compactMap { $0.kind == .file ? $0.filePaths.joined(separator: "\n") : $0.text }
        guard !texts.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texts.joined(separator: "\n"), forType: .string)
        monitor.markOwnChange()
        hide()
        postPaste()
    }

    // MARK: - Text recognition

    /// Recognizes text in images that have not been processed yet, one at a time in the background.
    private func runOCR() {
        guard !ocrRunning else { return }
        let pending = store.imagesNeedingOCR()
        guard !pending.isEmpty else { return }
        ocrRunning = true
        ocrQueue.async { [weak self] in
            for job in pending {
                let text = OCR.recognize(job.url)
                DispatchQueue.main.async { self?.store.setOCR(job.id, text) }
            }
            DispatchQueue.main.async { self?.finishOCR() }
        }
    }

    private func finishOCR() {
        ocrRunning = false
        reload()
        runOCR() // pick up images copied while this batch ran
    }

    /// Runs at launch and hourly: expire old history, then take the daily pinboard backup.
    private func prune() {
        store.prune(olderThan: Date().addingTimeInterval(-Double(retentionDays) * 86400))
        store.autoBackup()
        reload()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        if stackActive {
            button.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Shelf paste stack")
            button.title = " \(stackIndex + 1)/\(stackItems.count)"
        } else {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Shelf")
            button.title = ""
        }
        button.imagePosition = .imageLeading
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = menu.addItem(withTitle: "Open Shelf", action: #selector(openFromMenu), keyEquivalent: "")
        if let hotKey { open.title = "Open Shelf   \(hotKey.display)" } else { open.title = "Open Shelf (shortcut unavailable)" }

        if stackActive {
            menu.addItem(.separator())
            let next = menu.addItem(withTitle: "Paste Stack: next is \(stackIndex + 1) of \(stackItems.count)", action: nil, keyEquivalent: "")
            next.isEnabled = false
            menu.addItem(withTitle: "Skip to Next Item", action: #selector(skipStackItem), keyEquivalent: "")
            menu.addItem(withTitle: "End Paste Stack", action: #selector(endStackFromMenu), keyEquivalent: "")
        }
        menu.addItem(.separator())

        let pause = menu.addItem(withTitle: "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        pause.state = monitor.paused ? .on : .off
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Allow Auto-Paste…", action: #selector(openAccessibility), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Export Pinboards…", action: #selector(exportPinboards), keyEquivalent: "")
        menu.addItem(withTitle: "Import Pinboards…", action: #selector(importPinboards), keyEquivalent: "")
        menu.addItem(withTitle: "Show History Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Clear Unpinned History…", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func openFromMenu() {
        DispatchQueue.main.async { self.show() }
    }

    @objc private func skipStackItem() { advanceStack(after: 0) }

    @objc private func endStackFromMenu() { endStack() }

    @objc private func togglePause() { monitor.paused.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @objc private func openFolder() { NSWorkspace.shared.open(store.dir) }

    @objc private func exportPinboards() {
        NSApp.activate()
        let save = NSSavePanel()
        save.allowedContentTypes = [.json]
        save.nameFieldStringValue = "Shelf Pinboards \(Date().formatted(.iso8601.year().month().day())).json"
        save.message = "Pinboards may contain passwords and other secrets. Keep this file somewhere private."
        guard save.runModal() == .OK, let url = save.url else { return }
        do {
            try store.exportPinboards().write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func importPinboards() {
        NSApp.activate()
        let open = NSOpenPanel()
        open.allowedContentTypes = [.json]
        open.directoryURL = store.backupsDir
        guard open.runModal() == .OK, let url = open.url else { return }
        do {
            let result = try store.importPinboards(Data(contentsOf: url))
            reload()
            let alert = NSAlert()
            alert.messageText = "Imported \(result.items) items into \(result.boards) pinboards."
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear unpinned history?"
        alert.informativeText = "All items except pinned ones will be deleted from this Mac. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
            reload()
        }
    }
}
