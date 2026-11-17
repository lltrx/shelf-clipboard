import AppKit
import ServiceManagement
import UniformTypeIdentifiers
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

    /// SwiftUI content that draws its own shape and background (the paste box with its arrow).
    func hostPlain<V: View>(_ view: V) {
        contentView = NSHostingView(rootView: view)
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
    private let panelHeight: CGFloat = 312
    /// Tags ⌘V events Shelf posts itself, so the paste stack does not count them as yours.
    private static let syntheticMarker: Int64 = 0x5348_4C46

    private var store: Store!
    private let monitor = Monitor()
    private let screenshots = ScreenshotWatcher()
    private let model = ShelfModel()
    private let panel = ShelfPanel()
    private let preview = ShelfPanel()
    private let popover = ShelfPanel()   // the paste box, just above the selected card
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var shelfOpen = false                  // stays false while the shelf fades out
    private var panelAnimation = 0                 // bumped by show/hide, so a finished fade-out can't hide a reopened shelf
    private var commandHold: DispatchWorkItem?   // shows the ⌘ shortcuts once ⌘ has been held a moment
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
        model.plainEverywhere = UserDefaults.standard.bool(forKey: "pastePlainByDefault")
        model.askBeforePasting = UserDefaults.standard.object(forKey: "askBeforePasting") as? Bool ?? true
        model.appStyles = appStyles

        setUpPanels()
        setUpStatusItem()

        let spec = UserDefaults.standard.string(forKey: "hotkey") ?? "cmd+shift+v"
        hotKey = HotKey(spec: spec) { [unowned self] in toggle() }

        monitor.onCapture = { [unowned self] capture in
            if stackActive { endStack() } // you copied something new; the stack is over
            model.password = nil
            store.upsert(capture)
            reload()
            if capture.kind == .image { runOCR() }
        }
        monitor.ignoredApps = Set(ignoredApps)
        monitor.onConcealed = { [unowned self] in
            if stackActive { endStack() }
            model.password = monitor.concealedOnClipboard.map(ClipItem.concealedPlaceholder)
        }
        monitor.start()
        screenshots.onScreenshot = { [unowned self] url in addScreenshot(url) }
        if addScreenshots { screenshots.start() }

        prune()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.prune() }
        runOCR()
    }

    // MARK: - Panels

    private func setUpPanels() {
        panel.host(ShelfView(model: model))
        preview.host(PreviewView(model: model))
        preview.allowsKey = false
        popover.hostPlain(ExportView(model: model))
        popover.allowsKey = false

        // Hide only when focus leaves all the panels (moving into the editor or the paste box is fine).
        let focusCheck = { [unowned self] in
            DispatchQueue.main.async { [self] in
                if shelfOpen && !panel.isKeyWindow && !preview.isKeyWindow && !popover.isKeyWindow { hide() }
            }
        }
        panel.onResignKey = focusCheck
        preview.onResignKey = focusCheck
        popover.onResignKey = focusCheck
        // Clicking back into the shelf ends editing, or closes the Copy as File form.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [unowned self] _ in
            if model.editing { endEditing() }
            if model.exportDraft != nil { cancelExport() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] event in
            if event.window === popover { return handleExportKey(event) ? nil : event }
            if event.window === preview { return handleEditorKey(event) ? nil : event }
            guard event.window === panel else { return event }
            guard shelfOpen else { return nil }    // fading out: nothing more to do in it
            return handleKey(event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [unowned self] event in
            // Releasing ⌘ counts in any of Shelf's panels (⌘E and ⌘R move focus to the preview).
            if !event.modifierFlags.contains(.command) {
                commandChanged(false)
            } else if event.window === panel {
                commandChanged(true)
            }
            return event
        }
    }

    /// Holding ⌘ for a moment shows ⌘1…⌘9 on the cards and the ⌘ shortcuts at the bottom. The delay
    /// keeps them from flashing on every ⌘ shortcut, including the ⇧⌘V that opened the shelf.
    private func commandChanged(_ down: Bool) {
        commandHold?.cancel()
        commandHold = nil
        guard down else {
            model.commandHeld = false
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, NSEvent.modifierFlags.contains(.command), self.panel.isKeyWindow else { return }
            self.model.commandHeld = true
        }
        commandHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    /// Returns true when the key was handled by the shelf instead of the search field.
    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        let plain = shift != model.plainByDefault                       // ⇧ flips the default
        if !cmd && model.commandHeld { commandChanged(false) }           // missed ⌘'s release (e.g. in a menu)

        if model.naming != nil {                                         // typing a pinboard name
            if e.keyCode == 53 { model.naming = nil; model.pendingPin = nil; return true }
            return false
        }

        switch e.keyCode {
        case 53: model.previewing ? togglePreview() : hide(); return true   // esc
        case 123: model.move(cmd ? -1_000_000 : -1); return true            // ←
        case 124: model.move(cmd ? 1_000_000 : 1); return true              // →
        case 125 where !cmd: model.cycleKind(1); return true                // ↓ next kind: Text, Links…
        case 126 where !cmd: model.cycleKind(-1); return true               // ↑
        case 36, 76:                                                        // return (⇧ flips plain, ⌥ stack as one)
            if !model.stack.isEmpty {
                e.modifierFlags.contains(.option) ? pasteStackJoined() : startStack(plain: plain)
            } else if let item = model.selected {
                shift ? paste(item, plain: plain) : pasteFromCard(item)   // ⇧: images and files as they are
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
        case 15: model.selected.map(startExport); return true               // R: Copy as File… ("rename")
        case 8 where shift: model.selected.map(startExport); return true    // ⇧C: the same, as in betas 1–3
        case 8 where model.query.isEmpty: model.selected.map(copy); return true // C
        case 40: showPasteMenu(); return true                               // K: Paste As…
        case 45: model.startNaming(.new); return true                       // N
        case 43: showMenu(); return true                                    // , (Shelf menu)
        case 1:                                                             // S: add to stack, move on
            if let item = model.selected { model.toggleStack(item); model.move(1) }
            return true
        case 14: model.selected.map(edit); return true                      // E
        case let k where digitKeys.contains(k):
            let list = model.filtered
            let i = digitKeys.firstIndex(of: k)!
            if list.indices.contains(i) { paste(list[i], plain: plain) }
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
            pasteEdited(plain: e.modifierFlags.contains(.shift) != model.plainByDefault)
            return true
        default: return false
        }
    }

    /// Keys in the paste box. Everything else goes to the name field and the menus.
    private func handleExportKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 53: cancelExport(); return true                                // esc
        case 36, 76:                                                        // return
            if e.isARepeat { return true }   // Return held down: the repeat isn't a second Return
            if e.modifierFlags.contains(.shift), let draft = model.exportDraft, draft.source != .text {
                paste(draft.item, plain: false)                             // ⇧Return: the original
            } else {
                finishExport(.paste)
            }
            return true
        case 8 where cmd: finishExport(.copy); return true                  // ⌘C
        case 1 where cmd: finishExport(.save); return true                  // ⌘S
        default: return false
        }
    }

    private func toggle() {
        shelfOpen ? hide() : show()
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let target = NSRect(x: frame.minX + 8, y: frame.minY + 8, width: frame.width - 16, height: panelHeight)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        shelfOpen = true
        panelAnimation += 1
        // Starts a little low and transparent, then slides up into place (with Reduce Motion it only fades).
        panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 0, dy: -16), display: false)
        panel.alphaValue = 0
        // The shelf doesn't take focus from the app you're in, so that's where Return will paste.
        let front = NSWorkspace.shared.frontmostApplication
        if let front, let bundle = front.bundleIdentifier, bundle != Bundle.main.bundleIdentifier {
            model.target = ShelfModel.TargetApp(bundle: bundle, name: front.localizedName ?? Self.appName(bundle))
        } else {
            model.target = nil
        }
        // The shelf opens fresh, so resetting it isn't animated.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            model.query = ""
            model.tab = nil
            model.kindFilter = nil
            model.selection = 0
            model.stack = []
            model.naming = nil
            model.exportDraft = nil
            model.commandHeld = false
            model.password = monitor.concealedOnClipboard.map(ClipItem.concealedPlaceholder)
            model.now = Date()
            reload()
        }
        panel.makeKeyAndOrderFront(nil)
        model.focusTick += 1
        if addScreenshots { screenshots.start() }   // follows the screenshot folder if it was changed
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            self.panel.animator().alphaValue = 1
            self.panel.animator().setFrame(target, display: true)
        }
    }

    /// Closes the shelf. After a paste it closes at once, so the app underneath gets ⌘V straight
    /// away (and not the fading shelf); otherwise it fades out.
    private func hide(animated: Bool = true) {
        shelfOpen = false
        model.editing = false
        model.previewing = false
        model.naming = nil
        model.exportDraft = nil
        commandHold?.cancel()
        model.commandHeld = false
        preview.allowsKey = false
        preview.orderOut(nil)
        popover.allowsKey = false
        popover.orderOut(nil)
        panelAnimation += 1
        let generation = panelAnimation
        guard animated, panel.isVisible else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().alphaValue = 0
        }, completionHandler: {
            guard self.panelAnimation == generation else { return }   // reopened meanwhile
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    /// Brings a panel in with a short fade (fine with Reduce Motion too: nothing moves).
    private func fadeIn(_ window: NSWindow) {
        if !window.isVisible { window.alphaValue = 0 }
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
    }

    /// Moves or resizes a panel, smoothly when it's on screen (at once with Reduce Motion).
    private func place(_ window: NSWindow, _ frame: NSRect, animate: Bool) {
        guard animate, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
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
        cancelExport()
        if !model.previewing, model.selected?.concealed == true { return }
        model.previewing.toggle()
        guard model.previewing, panel.screen != nil else {
            endEditing()
            preview.orderOut(nil)
            return
        }
        placePreview()
        fadeIn(preview)
    }

    /// The preview's place: centered above the shelf, as tall as the screen allows.
    private func placePreview(animate: Bool = false) {
        guard let vf = panel.screen?.visibleFrame else { return }
        let bottom = panel.frame.maxY + 12
        let width = min(920, vf.width * 0.7)
        let height = max(220, min(580, vf.maxY - bottom - 12))
        place(preview, NSRect(x: vf.midX - width / 2, y: bottom, width: width, height: height), animate: animate)
    }

    func edit(_ item: ClipItem) {
        guard item.editable else { return }
        cancelExport()
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
        guard !item.concealed else { return }
        store.setBoard(item.id, board)
        reload()
    }

    /// ⌘P: unpin a pinned item; otherwise pin it, asking which board when there are several.
    private func requestPin() {
        guard let item = model.selected, !item.concealed else { return }
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
        if item.concealed {           // the password is already on the clipboard; just paste it
            hide(animated: false)
            postPaste()
            return
        }
        write(item, plain: plain)
        hide(animated: false)
        postPaste()
    }

    func copy(_ item: ClipItem) {
        guard !item.concealed else { hide(); return }   // already on the clipboard
        write(item)
        hide()
    }

    func delete(_ item: ClipItem) {
        guard !item.concealed else { return }
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

    // MARK: - Paste As

    /// ⌘K: every way to paste the selected card. A letter picks one while the menu is open.
    private func showPasteMenu() {
        guard let item = model.selected, !item.concealed, let view = panel.contentView else { return }
        let menu = NSMenu()
        for (i, section) in PasteOption.sections(for: item).enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            for option in section {
                let entry = NSMenuItem(title: option.title, action: #selector(pasteFromMenu(_:)), keyEquivalent: option.key)
                entry.keyEquivalentModifierMask = []
                entry.representedObject = PasteChoice(id: item.id, option: option)
                entry.target = self
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        let asFile = NSMenuItem(title: "Copy as File…", action: #selector(exportFromMenu(_:)), keyEquivalent: "e")
        asFile.keyEquivalentModifierMask = []
        asFile.representedObject = NSNumber(value: item.id)
        asFile.target = self
        menu.addItem(asFile)
        menu.popUp(positioning: menu.items.first, at: NSPoint(x: view.bounds.midX - 100, y: panelHeight - 44), in: view)
    }

    private struct PasteChoice {
        let id: Int64
        let option: PasteOption
    }

    @objc private func pasteFromMenu(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PasteChoice,
              let item = model.items.first(where: { $0.id == choice.id }) else { return }
        pasteAs(item, choice.option)
    }

    @objc private func exportFromMenu(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.int64Value,
              let item = model.items.first(where: { $0.id == id }) else { return }
        startExport(item)
    }

    func pasteAs(_ item: ClipItem, _ option: PasteOption) {
        switch option {
        case .original, .formatted:
            paste(item, plain: false)
        case .plain:
            paste(item, plain: true)
        case .markdown:
            pasteText(markdown(item), from: item)
        case .transform(let transform):
            guard let text = transform.apply(item.text ?? "") else { NSSound.beep(); return }
            pasteText(text, from: item)
        case .recognizedText:
            pasteText(item.ocr ?? "", from: item)
        case .paths:
            pasteText(item.filePaths.joined(separator: "\n"), from: item)
        case .names:
            pasteText(item.filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n"), from: item)
        }
    }

    /// Pastes text made from a card (changed case, Markdown…). It isn't recorded as a new card;
    /// the card it came from moves to the front, as after any paste.
    private func pasteText(_ text: String, from item: ClipItem) {
        guard !text.isEmpty else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        monitor.markOwnChange()
        store.touch(item.id)
        reload()
        hide(animated: false)
        postPaste()
    }

    /// Formatted text as Markdown, for Paste as Markdown and .md files.
    private func markdown(_ item: ClipItem) -> String {
        let rich = attributed(item)
        let string = rich.string as NSString
        var runs: [StyledRun] = []
        rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length), options: []) { attributes, range, _ in
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            var link: String?
            if let url = attributes[.link] as? URL {
                link = url.absoluteString
            } else if let text = attributes[.link] as? String {
                link = text
            }
            runs.append(StyledRun(string.substring(with: range), bold: traits.contains(.bold), italic: traits.contains(.italic),
                                  code: traits.contains(.monoSpace) || font?.isFixedPitch == true, link: link))
        }
        return MarkdownWriter.markdown(runs)
    }

    // MARK: - Copy as File

    /// Files made by Copy as File and by dragging images out. Deleted after a day.
    private var exportsDir: URL { store.dir.appendingPathComponent("Exports", isDirectory: true) }

    /// Return or double-click on a card: images and files open the paste box first (rename, resize,
    /// convert), unless that's turned off; everything else pastes.
    func pasteFromCard(_ item: ClipItem) {
        if model.askBeforePasting, !item.concealed, item.kind == .image || item.kind == .file {
            startExport(item)
        } else {
            paste(item, plain: model.plainByDefault)
        }
    }

    /// Opens the paste box above the selected card (Return on an image or file, ⌘R on any card). It
    /// starts from the card as it is, so Return without changes pastes the original.
    func startExport(_ item: ClipItem) {
        guard !item.concealed else { return }
        endEditing()
        let defaults = UserDefaults.standard
        var draft: ExportDraft
        switch item.kind {
        case .image:
            let name = ExportNaming.timestampName("Image", item.created)
            draft = ExportDraft(item: item, source: .image, originals: [name + ".png"], convertible: [true],
                                formats: FileExport.writableImageFormats, name: name, format: .png)
        case .text, .link:
            let name = ExportNaming.suggestedName(forText: item.text ?? "") ?? ExportNaming.timestampName("Text", item.created)
            let saved = ExportFormat(rawValue: defaults.string(forKey: "exportTextFormat") ?? "")
            draft = ExportDraft(item: item, source: .text, originals: [name + ".txt"], convertible: [true],
                                formats: ExportFormat.text, name: name,
                                format: saved.flatMap { ExportFormat.text.contains($0) ? $0 : nil } ?? .txt)
        case .file:
            let paths = item.filePaths
            let names = paths.map { ($0 as NSString).lastPathComponent }
            let convertible = paths.map(FileExport.isImage)
            let imageFormats = convertible.contains(true) ? FileExport.writableImageFormats : []
            // One image file in a format Shelf writes starts in that format, so Size works right
            // away; anything else starts as Keep Format.
            let own = paths.count == 1 && convertible[0]
                ? ExportFormat.of(extension: (paths[0] as NSString).pathExtension).flatMap { imageFormats.contains($0) ? $0 : nil }
                : nil
            draft = ExportDraft(item: item, source: .files, originals: names, convertible: convertible,
                                formats: own == nil ? [ExportFormat.original] + imageFormats : imageFormats,
                                name: names.count == 1 ? ExportNaming.splitExtension(names[0]).stem : "",
                                format: own ?? .original)
        }
        draft.startName = draft.name
        draft.startFormat = draft.format
        if defaults.object(forKey: "exportQuality") != nil {
            draft.quality = ExportDraft.nearestQuality(defaults.double(forKey: "exportQuality"))
        }
        model.exportDraft = draft
        showExportForm()
    }

    /// The paste box sits just above the shelf, its arrow pointing at the selected card.
    private func showExportForm() {
        guard let draft = model.exportDraft, let vf = panel.screen?.visibleFrame else { return }
        let width: CGFloat = 400
        let cardX = panel.frame.minX + (model.selectedCardMidX ?? panel.frame.width / 2)
        let x = min(max(cardX - width / 2, vf.minX + 8), vf.maxX - width - 8)
        model.popoverArrowX = cardX - x
        popover.setFrame(NSRect(x: x, y: panel.frame.maxY - 4, width: width, height: CGFloat(draft.popoverHeight)), display: true)
        popover.allowsKey = true
        fadeIn(popover)
        popover.makeKey()
    }

    /// Esc, or clicking back into the shelf: closes the paste box.
    func cancelExport() {
        guard model.exportDraft != nil else { return }
        model.exportDraft = nil
        popover.allowsKey = false
        popover.orderOut(nil)
        if panel.isVisible { panel.makeKey() }
    }

    /// Makes the files (off the main thread: images may need converting, files copying), then
    /// pastes, copies or saves them.
    func finishExport(_ action: ExportAction) {
        guard var draft = model.exportDraft, !draft.busy else { return }
        if draft.pastesOriginal && action != .save {   // nothing changed: the card itself, as before
            action == .paste ? paste(draft.item, plain: false) : copy(draft.item)
            return
        }
        let content: FileExport.Job.Content
        switch draft.source {
        case .text:
            do {
                let data = try textFileData(draft.item, draft.format)
                content = .data(data)
            } catch {
                model.exportDraft?.error = error.localizedDescription
                return
            }
        case .image:
            guard let url = store.imageURL(draft.item) else { return }
            content = .image(url)
        case .files:
            content = .files(draft.item.filePaths.map { URL(fileURLWithPath: $0) })
        }
        let job = FileExport.Job(content: content, names: draft.fileNames, format: draft.format,
                                 quality: draft.quality, scale: draft.scale, convert: draft.convertible)
        rememberExportChoices(draft)
        draft.busy = true
        draft.error = nil
        model.exportDraft = draft
        let form = draft.id
        let item = draft.item
        let root = exportsDir
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FileExport.write(job, in: root) }
            DispatchQueue.main.async { self.exportFinished(result, action, form: form, item: item) }
        }
    }

    private func exportFinished(_ result: Result<[URL], Error>, _ action: ExportAction, form: UUID, item: ClipItem) {
        guard model.exportDraft?.id == form else { return }   // that form was closed (or replaced) meanwhile
        switch result {
        case .failure(let error):
            model.exportDraft?.busy = false
            model.exportDraft?.error = error.localizedDescription
        case .success(let urls):
            switch action {
            case .paste, .copy:
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects(urls.map { $0 as NSURL })
                monitor.markOwnChange()
                store.touch(item.id)
                reload()
                hide(animated: action != .paste)
                if action == .paste { postPaste() }
            case .save:
                hide()
                saveExport(urls)
            }
        }
    }

    /// Save…: moves the files where you choose (Downloads to start with).
    private func saveExport(_ urls: [URL]) {
        NSApp.activate()
        // Then step aside, so the app you were in is frontmost again and ⇧⌘V pastes there.
        defer { NSApp.hide(nil) }
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        do {
            if urls.count == 1, let file = urls.first {
                let save = NSSavePanel()
                save.nameFieldStringValue = file.lastPathComponent
                save.directoryURL = downloads
                save.canCreateDirectories = true
                save.isExtensionHidden = false
                // Keeps the extension matching the contents if the name is changed here.
                if !file.pathExtension.isEmpty, let type = UTType(filenameExtension: file.pathExtension) {
                    save.allowedContentTypes = [type]
                }
                guard save.runModal() == .OK, let target = save.url else { return }
                if fm.fileExists(atPath: target.path) {   // the panel already asked about replacing it
                    _ = try fm.replaceItemAt(target, withItemAt: file)
                } else {
                    try fm.moveItem(at: file, to: target)
                }
            } else {
                let open = NSOpenPanel()
                open.canChooseFiles = false
                open.canChooseDirectories = true
                open.canCreateDirectories = true
                open.directoryURL = downloads
                open.prompt = "Save Here"
                open.message = "Choose a folder for the \(urls.count) files."
                guard open.runModal() == .OK, let folder = open.url else { return }
                let existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
                let names = ExportNaming.uniqued(urls.map(\.lastPathComponent), existing: existing)
                for (file, name) in zip(urls, names) {
                    try fm.moveItem(at: file, to: folder.appendingPathComponent(name))
                }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// The bytes of a text card saved as `format`.
    private func textFileData(_ item: ClipItem, _ format: ExportFormat) throws -> Data {
        let text = item.text ?? ""
        switch format {
        case .md:
            return Data((item.formatted ? markdown(item) : text).utf8)
        case .rtf, .docx, .html:
            if format == .html,
               let html = store.formats(item.id).first(where: { $0.type == NSPasteboard.PasteboardType.html.rawValue }) {
                return html.data   // the page's own HTML, as it was copied
            }
            let rich = exportAttributed(item)
            let type: NSAttributedString.DocumentType = format == .rtf ? .rtf : format == .docx ? .officeOpenXML : .html
            return try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: type])
        default:
            return Data(text.utf8)
        }
    }

    /// Unformatted cards are shown in the label color, which is white in Dark Mode; files get black text.
    private func exportAttributed(_ item: ClipItem) -> NSAttributedString {
        if item.formatted { return attributed(item) }
        let font = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        return NSAttributedString(string: item.text ?? "", attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    /// The next box starts with the quality (and, for text, the format) used last.
    private func rememberExportChoices(_ draft: ExportDraft) {
        let defaults = UserDefaults.standard
        if draft.source == .text { defaults.set(draft.format.rawValue, forKey: "exportTextFormat") }
        if draft.format.isLossy { defaults.set(draft.quality, forKey: "exportQuality") }
    }

    /// What a card carries when dragged out of the shelf. An image becomes a file with a readable
    /// name (a hard link to the stored PNG, so it takes no extra space).
    func dragItem(_ item: ClipItem) -> NSItemProvider? {
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .link:
            guard let url = URL(string: (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return NSItemProvider(object: url as NSURL)
        case .image:
            guard let source = store.imageURL(item) else { return nil }
            let fm = FileManager.default
            let dir = exportsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let file = dir.appendingPathComponent(ExportNaming.timestampName("Image", item.created) + ".png")
            guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil,
                  (try? fm.linkItem(at: source, to: file)) != nil || (try? fm.copyItem(at: source, to: file)) != nil
            else { return nil }
            return NSItemProvider(contentsOf: file)
        case .file:
            guard item.filePaths.count == 1, let path = item.filePaths.first else { return nil }
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Paste stack

    /// Pastes the first stacked item now; each ⌘V you press afterwards pastes the next one.
    private func startStack(plain: Bool) {
        let items = model.stack.compactMap { id in model.items.first { $0.id == id } }
        guard let first = items.first else { return }
        hide(animated: false)
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
        hide(animated: false)
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

    /// Runs at launch and hourly: expire old history and day-old exported files, then take the daily
    /// pinboard backup.
    private func prune() {
        store.prune(olderThan: Date().addingTimeInterval(-Double(retentionDays) * 86400))
        FileExport.prune(exportsDir)
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
        let shots = menu.addItem(withTitle: "Add Screenshots", action: #selector(toggleScreenshots), keyEquivalent: "")
        shots.state = addScreenshots ? .on : .off
        shots.toolTip = "Screenshots saved as files (⇧⌘3, ⇧⌘4, ⇧⌘5) appear in the shelf, ready to paste"
        let ask = menu.addItem(withTitle: "Ask Before Pasting Images and Files", action: #selector(toggleAskBeforePasting), keyEquivalent: "")
        ask.state = model.askBeforePasting ? .on : .off
        ask.toolTip = "Return opens a small box to rename, resize or convert first; ⇧Return pastes right away"
        let style = menu.addItem(withTitle: "Paste Style", action: nil, keyEquivalent: "")
        menu.setSubmenu(pasteStyleMenu(), for: style)
        let ignored = menu.addItem(withTitle: "Ignored Apps", action: nil, keyEquivalent: "")
        menu.setSubmenu(ignoredAppsMenu(), for: ignored)
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        menu.addItem(withTitle: "Shelf \(version)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Quit Shelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    /// The menu bar menu, shown from the shelf's ⋯ button or ⌘, (for when the menu bar icon is hidden).
    func showMenu() {
        guard let view = panel.contentView else { return }
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        // "Open Shelf" and its separator make no sense from inside the shelf.
        if menu.items.first?.action == #selector(openFromMenu) {
            menu.removeItem(at: 0)
            if menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX - 40, y: view.bounds.maxY - 34), in: view)
    }

    @objc private func openFromMenu() {
        DispatchQueue.main.async { self.show() }
    }

    @objc private func skipStackItem() { advanceStack(after: 0) }

    @objc private func endStackFromMenu() { endStack() }

    @objc private func togglePause() { monitor.paused.toggle() }

    @objc private func toggleScreenshots() { addScreenshots.toggle() }

    @objc private func toggleAskBeforePasting() {
        model.askBeforePasting.toggle()
        UserDefaults.standard.set(model.askBeforePasting, forKey: "askBeforePasting")
    }

    // MARK: - Screenshots

    /// Add Screenshots (on unless turned off): screenshot files appear in the shelf.
    private var addScreenshots: Bool {
        get { UserDefaults.standard.object(forKey: "addScreenshots") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "addScreenshots")
            newValue ? screenshots.start() : screenshots.stop()
        }
    }

    /// A new screenshot file: added to History as an image, as if it had been copied. Paused
    /// capture and an ignored Screenshot app skip it, as they do copies.
    private func addScreenshot(_ url: URL) {
        guard !monitor.paused, !monitor.ignoredApps.contains(ScreenshotWatcher.screenshotApp) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let capture = ScreenshotWatcher.capture(url) else { return }
            DispatchQueue.main.async { [self] in
                store.upsert(capture)
                reload()
                runOCR()
            }
        }
    }

    @objc private func useFormattedEverywhere() { setPlainEverywhere(false) }

    @objc private func usePlainEverywhere() { setPlainEverywhere(true) }

    private func setPlainEverywhere(_ plain: Bool) {
        model.plainEverywhere = plain
        UserDefaults.standard.set(plain, forKey: "pastePlainByDefault")
    }

    // MARK: - Paste style per app

    /// Bundle id → whether Return pastes plain text in that app. Only apps you set are listed;
    /// the rest follow the default (Shelf menu → Paste Style).
    private var appStyles: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: "pasteStyleByApp") as? [String: Bool] ?? [:] }
        set {
            UserDefaults.standard.set(newValue, forKey: "pasteStyleByApp")
            model.appStyles = newValue
        }
    }

    /// The control at the bottom right of the shelf: what Return pastes in the app you're pasting into.
    func showStyleMenu() {
        let menu = NSMenu()
        if let target = model.target {
            addStyleChoices(to: menu, heading: "Return in \(target.name) pastes", plain: model.plainByDefault,
                            formatted: #selector(useFormattedHere), plainText: #selector(usePlainHere))
            menu.addItem(.separator())
        }
        addStyleChoices(to: menu, heading: model.target == nil ? "Default for all apps" : "Default for other apps",
                        plain: model.plainEverywhere,
                        formatted: #selector(useFormattedEverywhere), plainText: #selector(usePlainEverywhere))
        menu.addItem(.separator())
        menu.addItem(withTitle: "⇧Return pastes the other way; ⌘K has more", action: nil, keyEquivalent: "").isEnabled = false
        popUpAtMouse(menu)
    }

    /// "With Formatting" and "Plain Text" as a pair of choices under a heading; the current one is checked.
    private func addStyleChoices(to menu: NSMenu, heading: String, plain: Bool, formatted: Selector, plainText: Selector) {
        menu.addItem(withTitle: heading, action: nil, keyEquivalent: "").isEnabled = false
        let withFormatting = NSMenuItem(title: "With Formatting", action: formatted, keyEquivalent: "")
        withFormatting.state = plain ? .off : .on
        withFormatting.toolTip = "Keeps fonts, colors, links and tables. ⇧Return pastes plain text."
        let plainOnly = NSMenuItem(title: "Plain Text", action: plainText, keyEquivalent: "")
        plainOnly.state = plain ? .on : .off
        plainOnly.toolTip = "Pastes just the text. ⇧Return keeps the formatting."
        for entry in [withFormatting, plainOnly] {
            entry.target = self
            entry.indentationLevel = 1
            menu.addItem(entry)
        }
    }

    @objc private func useFormattedHere() { setStyleHere(plain: false) }

    @objc private func usePlainHere() { setStyleHere(plain: true) }

    /// Sets what Return pastes in the app being pasted into (with no app, the default). A choice
    /// that matches the default isn't stored, so the app keeps following the default.
    private func setStyleHere(plain: Bool) {
        guard let bundle = model.target?.bundle else {
            setPlainEverywhere(plain)
            return
        }
        var styles = appStyles
        styles[bundle] = plain == model.plainEverywhere ? nil : plain
        appStyles = styles
    }

    /// Shelf menu → Paste Style: what Return pastes by default, and the apps set differently.
    private func pasteStyleMenu() -> NSMenu {
        let menu = NSMenu()
        addStyleChoices(to: menu, heading: "Return pastes", plain: model.plainEverywhere,
                        formatted: #selector(useFormattedEverywhere), plainText: #selector(usePlainEverywhere))
        menu.addItem(.separator())
        let styles = appStyles.map { (bundle: $0.key, name: Self.appName($0.key), plain: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let heading = styles.isEmpty ? "No apps set differently" : "Apps set differently (click one to use the default)"
        menu.addItem(withTitle: heading, action: nil, keyEquivalent: "").isEnabled = false
        for style in styles {
            let entry = NSMenuItem(title: "\(style.name): \(style.plain ? "Plain Text" : "With Formatting")",
                                   action: #selector(forgetAppStyle(_:)), keyEquivalent: "")
            entry.representedObject = style.bundle
            entry.indentationLevel = 1
            entry.toolTip = "Click to use the default in this app again"
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(withTitle: "Set an app at the bottom right of the shelf", action: nil, keyEquivalent: "").isEnabled = false
        return menu
    }

    @objc private func forgetAppStyle(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        var styles = appStyles
        styles[bundle] = nil
        appStyles = styles
    }

    private func popUpAtMouse(_ menu: NSMenu) {
        guard let view = panel.contentView else { return }
        let point = view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    // MARK: - Ignored apps

    /// Bundle ids whose copies are never recorded, in the order they were added.
    private var ignoredApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "ignoredApps") ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: "ignoredApps")
            monitor.ignoredApps = Set(newValue)
        }
    }

    func ignoreApp(_ item: ClipItem) {
        guard let bundle = item.sourceBundle, !ignoredApps.contains(bundle) else { return }
        ignoredApps.append(bundle)
    }

    private func ignoredAppsMenu() -> NSMenu {
        let menu = NSMenu()
        if ignoredApps.isEmpty {
            menu.addItem(withTitle: "No ignored apps", action: nil, keyEquivalent: "").isEnabled = false
        }
        for bundle in ignoredApps {
            let item = NSMenuItem(title: Self.appName(bundle), action: #selector(stopIgnoring(_:)), keyEquivalent: "")
            item.representedObject = bundle
            item.state = .on
            item.toolTip = "Click to record copies from this app again"
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let add = menu.addItem(withTitle: "Add App…", action: #selector(addIgnoredApp), keyEquivalent: "")
        add.target = self
        let note = menu.addItem(withTitle: "Password managers are always skipped", action: nil, keyEquivalent: "")
        note.isEnabled = false
        return menu
    }

    @objc private func stopIgnoring(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        ignoredApps.removeAll { $0 == bundle }
    }

    @objc private func addIgnoredApp() {
        NSApp.activate()
        let open = NSOpenPanel()
        open.allowedContentTypes = [.application]
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.prompt = "Ignore"
        open.message = "Shelf won't record anything copied in this app."
        guard open.runModal() == .OK, let url = open.url,
              let bundle = Bundle(url: url)?.bundleIdentifier, !ignoredApps.contains(bundle) else { return }
        ignoredApps.append(bundle)
    }

    static func appName(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

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
