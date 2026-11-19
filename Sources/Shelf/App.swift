import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Borderless panel that takes keyboard focus without activating Shelf,
/// so the app you were in stays frontmost and receives the paste.
final class ShelfPanel: NSPanel {
    var onResignKey: () -> Void = {}
    var allowsKey = true
    /// Asked at each mouse-down: whether a drag from there is Shelf's own (several cards at once).
    var ownsDrag: ((NSEvent) -> Bool)?
    /// Starts that drag, given the mouse-down and the first move.
    var startDrag: ((NSEvent, NSEvent) -> Void)?
    private enum DragState { case none, pending(NSEvent), started }
    private var drag = DragState.none

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

    /// SwiftUI's drag carries one item, so dragging several cards is started here, before SwiftUI
    /// sees the mouse move. Clicks still reach SwiftUI as usual.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            drag = ownsDrag?(event) == true ? .pending(event) : .none
        case .leftMouseDragged:
            switch drag {
            case .pending(let start):
                let dx = event.locationInWindow.x - start.locationInWindow.x
                let dy = event.locationInWindow.y - start.locationInWindow.y
                if dx * dx + dy * dy >= 9 {   // 3 points: a drag, not a shaky click
                    drag = .started
                    startDrag?(start, event)
                }
                return                        // SwiftUI mustn't start a drag of its own
            case .started:
                return
            case .none:
                break
            }
        case .leftMouseUp:
            drag = .none
        default:
            break
        }
        super.sendEvent(event)
    }

    /// SwiftUI content that draws its own shape and background (the paste box with its arrow).
    /// Its size is set from outside (the paste box grows for the image editor), not by the content.
    func hostPlain<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        contentView = hosting
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ShelfActions, SettingsActions {
    /// Unpinned history is kept this many days (0: forever). Settings → History.
    private var historyDays: Int { UserDefaults.standard.object(forKey: "historyDays") as? Int ?? 30 }
    /// Secrets (keys, tokens, passwords) are deleted after this many minutes (0: kept like any card).
    private var secretMinutes: Double { UserDefaults.standard.object(forKey: "secretMinutes") as? Double ?? 5 }
    private let panelHeight: CGFloat = 312
    /// Tags ⌘V events Shelf posts itself, so the paste stack does not count them as yours.
    private static let syntheticMarker: Int64 = 0x5348_4C46

    private var store: Store!
    private let monitor = Monitor()
    private let screenshots = ScreenshotWatcher()
    private let model = ShelfModel()
    private let settings = SettingsModel()
    private var settingsWindow: NSWindow?
    private var prunedDays: Int?   // the history length the last prune used
    private let panel = ShelfPanel()
    private let preview = ShelfPanel()
    private let popover = ShelfPanel()   // the paste box, just above the selected card
    private var hotKeys: [GlobalShortcut: HotKey] = [:]   // open the shelf, paste previous, grab text
    private let toast = Toast()
    private var grabbing = false
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var shelfOpen = false                  // stays false while the shelf fades out
    private var panelAnimation = 0                 // bumped by show/hide, so a finished fade-out can't hide a reopened shelf
    private var commandHold: DispatchWorkItem?   // shows the ⌘ shortcuts once ⌘ has been held a moment
    private var pruneTimer: Timer?
    private var expiryTimer: Timer?
    private var undoGroups: [[ItemSnapshot]] = []   // deleted cards, newest group last, for ⌘Z

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
        settings.actions = self
        model.plainEverywhere = UserDefaults.standard.bool(forKey: "pastePlainByDefault")
        model.askBeforePasting = UserDefaults.standard.object(forKey: "askBeforePasting") as? Bool ?? true
        model.appStyles = appStyles

        setUpPanels()
        setUpStatusItem()

        registerHotKeys()

        monitor.onCapture = { [unowned self] copied in
            if stackActive { endStack() } // you copied something new; the stack is over
            model.password = nil
            record(cleanLinks ? withoutTracking(copied) : copied)
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
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.expireSecrets() }
        runOCR()
    }

    // MARK: - Panels

    private func setUpPanels() {
        panel.host(ShelfView(model: model))
        preview.host(PreviewView(model: model))
        preview.allowsKey = false
        popover.hostPlain(ExportView(model: model))
        popover.allowsKey = false
        panel.ownsDrag = { [unowned self] event in !severalToDrag(at: event).isEmpty }
        panel.startDrag = { [unowned self] start, event in dragSeveral(severalToDrag(at: start), with: event) }

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
            if let window = settingsWindow, event.window === window { return handleSettingsKey(event) ? nil : event }
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
            if e.keyCode == 53 { model.naming = nil; model.pendingPins = []; return true }
            return false
        }

        switch e.keyCode {
        case 53: model.previewing ? togglePreview() : hide(); return true   // esc
        case 123: shift && !cmd ? extendMarks(-1) : model.move(cmd ? -1_000_000 : -1); return true   // ← (⇧ marks)
        case 124: shift && !cmd ? extendMarks(1) : model.move(cmd ? 1_000_000 : 1); return true      // → (⇧ marks)
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
        case 51 where cmd:                                                  // ⌘⌫: the marked cards, else this one
            if model.stack.isEmpty {
                model.selected.map(delete)
            } else {
                deleteItems(model.stack.compactMap { id in model.items.first { $0.id == id } })
            }
            return true
        default: break
        }

        // Physical key codes, so shortcuts work with any keyboard layout (e.g. Arabic).
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1…9
        guard cmd else { return false }
        switch e.keyCode {
        case 35: requestPin(); return true                                  // P
        case 6 where model.query.isEmpty && !shift: undoDelete(); return true   // Z: undo delete
        case 38: joinMarked(); return true                                  // J: join the marked cards
        case 15: model.selected.map(startExport); return true               // R: Copy as File… ("rename")
        case 8 where shift: model.selected.map(startExport); return true    // ⇧C: the same, as in betas 1–3
        case 8 where model.query.isEmpty: model.selected.map(copy); return true // C
        case 40: showPasteMenu(); return true                               // K: Paste As…
        case 45: model.startNaming(.new); return true                       // N
        case 43: showSettings(); return true                                // ,: Settings
        case 1:                                                             // S: add to stack, move on
            if let item = model.selected { model.toggleStack(item); model.move(1) }
            return true
        case 14:                                                            // E: Markup (images), Edit (text)
            if let item = model.selected { item.canMarkup ? markup(item) : edit(item) }
            return true
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
        if model.exportDraft?.editor != nil { return handleImageEditorKey(e) }
        switch e.keyCode {
        case 53: cancelExport(); return true                                // esc
        case 36, 76:                                                        // return
            if e.isARepeat { return true }   // Return held down: the repeat isn't a second Return
            if model.exportFocus == .markup && !e.modifierFlags.contains(.shift) {
                openImageEditor()                                           // on Markup (Tab): open it
                return true
            }
            if e.modifierFlags.contains(.shift), let draft = model.exportDraft, draft.source != .text {
                paste(draft.item, plain: false)                             // ⇧Return: the original
            } else {
                finishExport(.paste)
            }
            return true
        case 8 where cmd: finishExport(.copy); return true                  // ⌘C
        case 1 where cmd: finishExport(.save); return true                  // ⌘S
        case 14 where cmd: openImageEditor(); return true                   // ⌘E: blur and crop
        case 48:                                                            // tab, ⇧tab: next control
            if let draft = model.exportDraft {
                model.exportFocus = draft.field(after: model.exportFocus, backward: e.modifierFlags.contains(.shift))
            }
            return true
        case 123, 124, 125, 126:                                            // arrows change that control
            // (A `where` here would only guard the last key code, so check inside.)
            guard !cmd, model.exportFocus != .name else { return false }   // in the name: the text cursor
            let arrow: ExportDraft.Arrow
            switch e.keyCode {
            case 123: arrow = .left
            case 124: arrow = .right
            case 125: arrow = .down
            default: arrow = .up
            }
            model.exportDraft?.change(model.exportFocus, arrow)
            if let draft = model.exportDraft, !draft.fields.contains(model.exportFocus) {
                model.exportFocus = .format   // a format without quality: Quality is gone
            }
            return true
        default: return false
        }
    }

    /// Keys in the image editor. While text is being typed, the text field gets them (Return keeps
    /// the text, Esc removes it); otherwise the editor takes every key.
    private func handleImageEditorKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        if model.exportDraft?.editor?.typing != nil {
            switch e.keyCode {
            case 36, 76: model.exportDraft?.finishTyping(keep: true); return true
            case 53: model.exportDraft?.finishTyping(keep: false); return true
            default: return false
            }
        }
        let colorKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26]               // 1…7
        let selected = model.exportDraft?.editor?.selected != nil
        let option = e.modifierFlags.contains(.option)
        let step = e.modifierFlags.contains(.shift) ? 0.05 : 0.01           // ⇧: bigger steps
        switch e.keyCode {
        case 53:                                                            // esc: let go, then as it was
            if selected { model.exportDraft?.select(nil) } else { closeImageEditor(keep: false) }
        case 36, 76:                                                        // return: change the text, or done
            guard !e.isARepeat else { break }
            if model.exportDraft?.editSelectedText() != true { closeImageEditor(keep: true) }
        case 49 where !cmd: model.exportDraft?.addInMiddle()                // space: add one in the middle
        case 48: model.exportDraft?.selectNext(backward: e.modifierFlags.contains(.shift))   // tab: next item
        case 123, 124, 125, 126:                                            // arrows: move (⌥: resize)
            guard !cmd else { break }   // (a `where` here would only guard the last key code)
            var dx = 0.0, dy = 0.0
            switch e.keyCode {
            case 123: dx = -step
            case 124: dx = step
            case 125: dy = step
            default: dy = -step
            }
            if option { model.exportDraft?.resizeSelected(dw: dx, dh: dy) } else { model.exportDraft?.moveSelected(dx: dx, dy: dy) }
        case 6 where cmd: model.exportDraft?.undoEdit()                     // ⌘Z
        case 51, 117: model.exportDraft?.deleteSelected()                   // ⌫: the selected item, or everything
        case 14 where cmd: closeImageEditor(keep: true)                     // ⌘E again
        default:
            guard !cmd else { break }
            if let index = colorKeys.firstIndex(of: e.keyCode), MarkColor.allCases.indices.contains(index) {
                model.exportDraft?.setColor(MarkColor.allCases[index])
            } else if let tool = EditTool.allCases.first(where: { $0.keyCode == e.keyCode }) {
                model.exportDraft?.setTool(tool)                            // A R H T B C
            }
        }
        return true
    }

    /// Keys in Settings: all of them while a shortcut is being recorded, and ⌘W (Shelf has no menu
    /// bar of its own to close windows with).
    private func handleSettingsKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags
        if settings.recording != nil {
            let usable = settings.record(keyCode: e.keyCode, command: flags.contains(.command), option: flags.contains(.option),
                                         shift: flags.contains(.shift), control: flags.contains(.control))
            if !usable { NSSound.beep() }
            return true
        }
        if e.keyCode == 13, flags.contains(.command) {
            settingsWindow?.performClose(nil)
            return true
        }
        return false
    }

    private func toggle() {
        shelfOpen ? hide() : show()
    }

    /// The global shortcuts, from settings. Called again when Settings changes one. Returns the
    /// ones another app already has.
    @discardableResult
    func registerHotKeys() -> Set<GlobalShortcut> {
        hotKeys = [:]   // releasing a HotKey unregisters it, so the same keys can be taken again
        var failed: Set<GlobalShortcut> = []
        for shortcut in GlobalShortcut.allCases {
            guard let spec = shortcut.spec(stored: UserDefaults.standard.string(forKey: shortcut.key)) else { continue }  // off
            let action: () -> Void
            switch shortcut {
            case .open: action = { [unowned self] in toggle() }
            case .previous: action = { [unowned self] in pastePrevious() }
            case .grabText: action = { [unowned self] in grabText() }
            }
            if let hotKey = HotKey(spec: spec.spec, handler: action) {
                hotKeys[shortcut] = hotKey
            } else {
                failed.insert(shortcut)
            }
        }
        return failed
    }

    /// ⌥⇧⌘V anywhere: pastes the copy before the current one, without opening the shelf. Pressing
    /// it again swaps back, since the one just pasted is now the newest.
    private func pastePrevious() {
        let items = store.all()
        guard items.count > 1 else { NSSound.beep(); return }
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let plain = bundle.flatMap { appStyles[$0] } ?? model.plainEverywhere
        paste(items[1], plain: plain)
    }

    private func show() {
        // Shelf steps aside (hides) after Save… and Settings; its panels need it shown again.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
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
            model.canAutoPaste = AXIsProcessTrusted()
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

    /// ⌘P: pins the marked cards (or the selected one), asking which pinboard when there are
    /// several; if they're all pinned already, unpins them.
    private func requestPin() {
        let marked = model.stack.compactMap { id in model.items.first { $0.id == id } }
        let items = (marked.isEmpty ? [model.selected].compactMap { $0 } : marked).filter { !$0.concealed }
        guard !items.isEmpty else { return }
        if items.allSatisfy(\.pinned) {
            items.forEach { store.setBoard($0.id, nil) }
            model.stack = []
            reload()
            return
        }
        let ids = items.map(\.id)
        if model.boards.isEmpty { model.pendingPins = ids; model.startNaming(.new); return }
        if model.boards.count == 1 { pin(ids, model.boards[0].id); return }

        let menu = NSMenu()
        for (i, board) in model.boards.enumerated() {
            let entry = NSMenuItem(title: board.name, action: #selector(pinFromMenu(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            entry.keyEquivalentModifierMask = []
            entry.tag = Int(board.id)
            entry.representedObject = ids.map { NSNumber(value: $0) }
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let new = NSMenuItem(title: "New Pinboard…", action: #selector(newBoardFromMenu(_:)), keyEquivalent: "n")
        new.keyEquivalentModifierMask = []
        new.representedObject = ids.map { NSNumber(value: $0) }
        new.target = self
        menu.addItem(new)
        popUpAboveShelf(menu)
    }

    /// Opens a menu just above the shelf, by the selected card. The shelf sits at the bottom of the
    /// screen, so a menu opening downward from it runs off shorter screens.
    private func popUpAboveShelf(_ menu: NSMenu) {
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let size = menu.size
        let cardX = panel.frame.minX + (model.selectedCardMidX ?? panel.frame.width / 2)
        let x = min(max(cardX - 60, visible.minX + 4), visible.maxX - size.width - 4)
        let top = min(panel.frame.maxY - 30 + size.height, visible.maxY)   // its top left, in screen points
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: top), in: nil)
    }

    private func pin(_ ids: [Int64], _ board: Int64) {
        ids.forEach { store.setBoard($0, board) }
        model.stack = []
        reload()
    }

    @objc private func pinFromMenu(_ sender: NSMenuItem) {
        guard let ids = (sender.representedObject as? [NSNumber])?.map(\.int64Value) else { return }
        pin(ids, Int64(sender.tag))
    }

    @objc private func newBoardFromMenu(_ sender: NSMenuItem) {
        model.pendingPins = (sender.representedObject as? [NSNumber])?.map(\.int64Value) ?? []
        model.startNaming(.new)
    }

    func commitName() {
        let name = model.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { model.naming = nil; model.pendingPins = []; reload() }
        guard !name.isEmpty, let naming = model.naming else { return }
        switch naming {
        case .new:
            let board = store.createBoard(name)
            if model.pendingPins.isEmpty { model.tab = board } else { pin(model.pendingPins, board) }
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
        // A pinned snippet with {{date}}, {{clipboard}}… is filled in and pasted as plain text.
        if item.pinned, item.kind == .text || item.kind == .link, let text = item.text, Snippet.hasPlaceholders(text) {
            pasteText(Snippet.expand(text, clipboard: NSPasteboard.general.string(forType: .string)), from: item)
            return
        }
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
        deleteItems([item])
    }

    /// Deletes cards, keeping what ⌘Z needs to put them back (the last 20 deletions).
    private func deleteItems(_ items: [ClipItem]) {
        let items = items.filter { !$0.concealed }
        guard !items.isEmpty else { return }
        let snaps = items.compactMap { store.snapshot($0.id) }
        for item in items { store.delete(item.id) }
        if !snaps.isEmpty {
            undoGroups.append(snaps)
            if undoGroups.count > 20 { undoGroups.removeFirst() }
        }
        model.canUndo = !undoGroups.isEmpty
        let gone = Set(items.map(\.id))
        model.stack.removeAll { gone.contains($0) }
        reload()
    }

    /// ⌘Z: puts the last deleted cards back where they were, and selects them.
    private func undoDelete() {
        guard let group = undoGroups.popLast() else { NSSound.beep(); return }
        let ids = group.compactMap { store.restore($0) }
        model.canUndo = !undoGroups.isEmpty
        reload()
        if let first = ids.first, let index = model.filtered.firstIndex(where: { $0.id == first }) {
            model.selection = index
        }
    }

    /// ⌘J: the marked cards' text joined into one new card, one per line, which is then selected.
    private func joinMarked() {
        let marked = model.stack.compactMap { id in model.items.first { $0.id == id } }
        let parts = marked.compactMap { $0.kind == .file ? $0.filePaths.joined(separator: "\n") : $0.text }.filter { !$0.isEmpty }
        guard parts.count > 1 else { NSSound.beep(); return }
        let text = parts.joined(separator: "\n")
        let capture = Capture(kind: Monitor.isLink(text) ? .link : .text, text: text, hash: Monitor.digest("text", Data(text.utf8)),
                              sourceBundle: Bundle.main.bundleIdentifier, sourceName: "Shelf")
        guard let id = store.upsert(capture) else { return }
        model.stack = []
        reload()
        if let index = model.filtered.firstIndex(where: { $0.id == id }) { model.selection = index }
    }

    /// ⇧← ⇧→: marks this card and the next, like selecting several in a list.
    private func extendMarks(_ delta: Int) {
        if let item = model.selected, !item.concealed, !model.stack.contains(item.id) { model.toggleStack(item) }
        model.move(delta)
        if let item = model.selected, !item.concealed, !model.stack.contains(item.id) { model.toggleStack(item) }
    }

    /// Sends ⌘V to the frontmost app. Needs Accessibility; without it the item just stays on the clipboard.
    /// The system prompt is shown at most once per launch; after that, use "Allow Auto-Paste…" in the menu.
    private func postPaste() {
        guard AXIsProcessTrusted() else {
            // Without Accessibility, Shelf can't press ⌘V. The item is on the clipboard, so say so (the
            // shelf also shows "Return only copies" with a way to fix it).
            toast.show("Copied · press ⌘V to paste (auto-paste is off)", symbol: "doc.on.clipboard")
            if !axPrompted {
                axPrompted = true
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            model.canAutoPaste = false
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
        guard let item = model.selected, !item.concealed else { return }
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
        popUpAboveShelf(menu)
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
        case .lineByLine:
            let lines = TextTools.stackLines(item.text ?? "")
            guard lines.count > 1 else { NSSound.beep(); return }
            store.touch(item.id)
            // Each line as a card of its own, only for the stack (never stored).
            let cards = lines.map { line in
                ClipItem(id: -1, kind: Monitor.isLink(line) ? .link : .text, text: line, image: nil, detail: nil,
                         sourceBundle: item.sourceBundle, sourceName: item.sourceName, created: Date(), board: nil,
                         formatted: false, ocr: nil)
            }
            beginStack(cards, plain: true)
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
    func startExport(_ item: ClipItem) { openExport(item, markup: false) }

    /// ⌘E (or right-click → Markup…) on an image card: the paste box opens straight into Markup. Done
    /// leads to the box (paste, copy or save the result); Esc closes it all.
    func markup(_ item: ClipItem) { openExport(item, markup: true) }

    private func openExport(_ item: ClipItem, markup: Bool) {
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
        if markup && draft.canEdit {
            draft.beginEditing()
            draft.openedForMarkup = true
        }
        model.exportFocus = .name
        if defaults.object(forKey: "exportQuality") != nil {
            draft.quality = ExportDraft.nearestQuality(defaults.double(forKey: "exportQuality"))
        }
        model.exportDraft = draft
        showExportForm()
    }

    /// The paste box sits just above the shelf, its arrow pointing at the selected card.
    private func showExportForm() {
        layoutExportForm()
        popover.allowsKey = true
        fadeIn(popover)
        popover.makeKey()
    }

    /// Sizes and places the paste box: 440 points wide, or as big as fits (up to 640 × 480) while
    /// the image editor is open.
    private func layoutExportForm() {
        guard let draft = model.exportDraft, let vf = panel.screen?.visibleFrame else { return }
        let bottom = panel.frame.maxY - 4
        let size = draft.editor == nil
            ? CGSize(width: 440, height: draft.popoverHeight)
            : CGSize(width: min(640, vf.width - 16), height: max(260, min(480, vf.maxY - bottom - 8)))
        let cardX = panel.frame.minX + (model.selectedCardMidX ?? panel.frame.width / 2)
        let x = min(max(cardX - size.width / 2, vf.minX + 8), vf.maxX - size.width - 8)
        model.popoverArrowX = cardX - x
        model.popoverSize = size
        popover.setFrame(NSRect(x: x, y: bottom, width: size.width, height: size.height), display: true)
    }

    /// ⌘E or Markup in the paste box: the box grows to show the image.
    func openImageEditor() {
        guard var draft = model.exportDraft, draft.canEdit, !draft.busy, draft.editor == nil else { return }
        draft.beginEditing()
        model.exportDraft = draft
        layoutExportForm()
    }

    /// Done (keep) or Esc: back to the box, which then pastes, copies or saves the edited image. Esc
    /// after ⌘E on a card closes the box too: it was opened for Markup.
    func closeImageEditor(keep: Bool) {
        guard let draft = model.exportDraft, draft.editor != nil else { return }
        if !keep && draft.openedForMarkup {
            cancelExport()
            return
        }
        model.exportDraft?.endEditing(keep: keep)
        model.exportDraft?.openedForMarkup = false
        layoutExportForm()
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
        guard var draft = model.exportDraft, !draft.busy, draft.editor == nil else { return }
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
        let job = FileExport.Job(content: content, names: draft.fileNames, format: draft.outputFormat,
                                 quality: draft.quality, scale: draft.scale, convert: draft.convertible,
                                 edits: draft.edits)
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
            return dragFile(for: item).flatMap { NSItemProvider(contentsOf: $0) }
        case .file:
            guard item.filePaths.count == 1, let path = item.filePaths.first else { return nil }
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path))
        }
    }

    /// An image card as a PNG file with a readable name, for dragging.
    private func dragFile(for item: ClipItem) -> URL? {
        guard let source = store.imageURL(item) else { return nil }
        let fm = FileManager.default
        let dir = exportsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent(ExportNaming.timestampName("Image", item.created) + ".png")
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil,
              (try? fm.linkItem(at: source, to: file)) != nil || (try? fm.copyItem(at: source, to: file)) != nil
        else { return nil }
        return file
    }

    /// The cards a drag starting at `event` carries, when it's more than SwiftUI's single item: the
    /// marked cards (when the drag starts on one of them), or a card holding several files.
    private func severalToDrag(at event: NSEvent) -> [ClipItem] {
        guard shelfOpen, model.exportDraft == nil, let view = panel.contentView else { return [] }
        let p = event.locationInWindow
        let point = CGPoint(x: p.x, y: view.bounds.height - p.y)   // SwiftUI's frames run down from the top
        guard let id = model.cardFrames.first(where: { $0.value.contains(point) })?.key,
              let item = model.items.first(where: { $0.id == id }), !item.concealed else { return [] }
        if model.stack.count > 1, model.stack.contains(id) {
            return model.stack.compactMap { marked in model.items.first { $0.id == marked && !$0.concealed } }
        }
        return item.kind == .file && item.filePaths.count > 1 ? [item] : []
    }

    /// Drags several cards (or files) out at once, as a pile under the mouse. Files and images go as
    /// files, links as links, text as text.
    private func dragSeveral(_ items: [ClipItem], with event: NSEvent) {
        guard !items.isEmpty, let view = panel.contentView else { return }
        let origin = view.convert(event.locationInWindow, from: nil)
        var dragging: [NSDraggingItem] = []
        func add(_ writer: NSPasteboardWriting, _ icon: NSImage?) {
            let item = NSDraggingItem(pasteboardWriter: writer)
            let n = CGFloat(min(dragging.count, 6))
            item.setDraggingFrame(NSRect(x: origin.x - 24 + n * 5, y: origin.y - 24 - n * 5, width: 48, height: 48),
                                  contents: icon)
            dragging.append(item)
        }
        for item in items {
            switch item.kind {
            case .file:
                for path in item.filePaths {
                    add(URL(fileURLWithPath: path) as NSURL, NSWorkspace.shared.icon(forFile: path))
                }
            case .image:
                guard let file = dragFile(for: item) else { continue }
                add(file as NSURL, NSImage(contentsOf: file))
            case .link:
                let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: text) else { continue }
                add(url as NSURL, NSImage(systemSymbolName: "link", accessibilityDescription: nil))
            case .text:
                add((item.text ?? "") as NSString, NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil))
            }
        }
        guard !dragging.isEmpty else { return }
        let session = view.beginDraggingSession(with: dragging, event: event, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - Paste stack

    /// Pastes the first stacked item now; each ⌘V you press afterwards pastes the next one.
    private func startStack(plain: Bool) {
        beginStack(model.stack.compactMap { id in model.items.first { $0.id == id } }, plain: plain)
    }

    /// The marked cards, or a card's lines (Paste Lines One by One).
    private func beginStack(_ items: [ClipItem], plain: Bool) {
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
        prunedDays = historyDays
        if historyDays > 0 { store.prune(olderThan: Date().addingTimeInterval(-Double(historyDays) * 86400)) }
        store.deleteExpired()
        FileExport.prune(exportsDir)
        store.autoBackup()
        reload()
    }

    /// Adds a copy to History (secrets get their expiry) and refreshes the shelf.
    private func record(_ capture: Capture) {
        let id = store.upsert(capture)
        if let id, secretMinutes > 0, capture.kind == .text || capture.kind == .link,
           let text = capture.text, SecretScanner.kind(of: text) != nil {
            store.setExpiry(id, Date().addingTimeInterval(secretMinutes * 60))
        }
        reload()
        if capture.kind == .image { runOCR() }
    }

    // MARK: - Grab text from screen

    /// ⇧⌘2 anywhere (or the Shelf menu): drag over part of the screen, like a screenshot. The text
    /// in it is recognized on this Mac, put on the clipboard and added to History. Space while
    /// choosing picks a whole window; Esc cancels.
    func grabText() {
        guard !grabbing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            // The first time, macOS shows its own prompt; after that, the setting has to be turned on.
            if SettingsModel.askForScreenCapture() {
                toast.show("Allow Shelf in Screen Recording, then try again", symbol: "lock.shield")
            }
            return
        }
        grabbing = true
        if shelfOpen { hide(animated: false) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-grab-\(UUID().uuidString).png")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = OCR.grabFromScreen(file)
            DispatchQueue.main.async { self?.grabFinished(text) }
        }
    }


    private func grabFinished(_ recognized: String?) {
        grabbing = false
        guard let recognized else { return }
        if stackActive { endStack() }   // new text on the clipboard ends the stack, as a copy would
        let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            toast.show("No text found there", symbol: "text.viewfinder")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        monitor.markOwnChange()
        record(Capture(kind: Monitor.isLink(text) ? .link : .text, text: text, hash: Monitor.digest("text", Data(text.utf8)),
                       sourceBundle: Bundle.main.bundleIdentifier, sourceName: "Text from Screen"))
        let words = text.split(whereSeparator: \.isWhitespace).count
        toast.show(words == 1 ? "Copied 1 word · ⌘V to paste" : "Copied \(words) words · ⌘V to paste", symbol: "text.viewfinder")
    }

    /// Remove tracking from copied links (Settings; on unless turned off).
    private var cleanLinks: Bool { UserDefaults.standard.object(forKey: "cleanLinks") as? Bool ?? true }

    /// A copied link without utm_…, fbclid, gclid and the like, on its card and on the clipboard (so
    /// ⌘V pastes it clean too). Anything else, or a link with no tracking, is left as it is.
    private func withoutTracking(_ capture: Capture) -> Capture {
        guard capture.kind == .link, let text = capture.text, let clean = TextTools.removeTracking(text) else { return capture }
        var out = capture
        out.text = clean
        out.formats = []
        out.hash = Monitor.digest("text", Data(clean.utf8))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(clean, forType: .string)
        pb.setString(clean, forType: .URL)
        monitor.markOwnChange()
        return out
    }

    /// Every 30 seconds: secrets whose time is up are deleted (and open cards' countdowns refresh).
    private func expireSecrets() {
        if store.deleteExpired() { reload() }
        if shelfOpen { model.now = Date() }
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

    // MARK: - Settings

    /// ⌘, in the shelf, or Settings… in the Shelf menu.
    @objc func showSettings() {
        if shelfOpen { hide(animated: false) }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Shelf Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                   queue: .main) { [weak self] _ in
                self?.settings.stopRecording()
                // Then step aside, so the app you were in is frontmost again and ⇧⌘V pastes there.
                DispatchQueue.main.async { NSApp.hide(nil) }
            }
            // Switching to another app mid-recording would otherwise leave the shortcuts off.
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                   queue: .main) { [weak self] _ in
                self?.settings.stopRecording()
            }
            settingsWindow = window
        }
        if NSApp.isHidden { NSApp.unhide(nil) }   // closing Settings (or Save…) hid Shelf
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applyShortcuts() -> Set<GlobalShortcut> { registerHotKeys() }

    func pauseShortcuts() { hotKeys = [:] }

    /// Settings wrote new values: refresh what the app keeps at hand.
    func settingsChanged() {
        let defaults = UserDefaults.standard
        model.plainEverywhere = defaults.bool(forKey: "pastePlainByDefault")
        model.askBeforePasting = defaults.object(forKey: "askBeforePasting") as? Bool ?? true
        model.appStyles = appStyles
        monitor.ignoredApps = Set(ignoredApps)
        if addScreenshots { screenshots.start() } else { screenshots.stop() }
        if historyDays != prunedDays { prune() }   // a shorter history takes effect now
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = menu.addItem(withTitle: "Open Shelf", action: #selector(openFromMenu), keyEquivalent: "")
        if let hotKey = hotKeys[.open] { open.title = "Open Shelf   \(hotKey.display)" } else { open.title = "Open Shelf (shortcut unavailable)" }
        let grab = menu.addItem(withTitle: "Grab Text from Screen", action: #selector(grabFromMenu), keyEquivalent: "")
        if let hotKey = hotKeys[.grabText] { grab.title = "Grab Text from Screen   \(hotKey.display)" }

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
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Turn On Auto-Paste…", action: #selector(openAccessibility), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Export Pinboards…", action: #selector(exportPinboards), keyEquivalent: "")
        menu.addItem(withTitle: "Import Pinboards…", action: #selector(importPinboards), keyEquivalent: "")
        menu.addItem(withTitle: "Show History Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Forget Last 5 Minutes", action: #selector(forgetRecent), keyEquivalent: "")
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

    @objc private func grabFromMenu() {
        DispatchQueue.main.async { self.grabText() }   // once the menu has closed
    }

    @objc private func skipStackItem() { advanceStack(after: 0) }

    @objc private func endStackFromMenu() { endStack() }

    @objc private func togglePause() { monitor.paused.toggle() }

    // MARK: - Screenshots

    /// Add Screenshots (Settings; on unless turned off): screenshot files appear in the shelf.
    private var addScreenshots: Bool { UserDefaults.standard.object(forKey: "addScreenshots") as? Bool ?? true }

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

    static func appName(_ bundle: String) -> String { AppName.of(bundle) }

    @objc private func openAccessibility() { fixAutoPaste() }

    /// Auto-paste needs Accessibility. Each new build (every beta) is a new app to macOS, so an old
    /// "Shelf" entry in that list can look switched on and still not count, and then macOS doesn't
    /// ask again. This removes Shelf's entry, asks again, and opens the Accessibility settings, where
    /// Shelf can be switched on.
    func fixAutoPaste() {
        if shelfOpen { hide(animated: false) }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.turkifaisal.shelf"]
        if (try? reset.run()) != nil { reset.waitUntilExit() }
        axPrompted = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        toast.show("Switch Shelf on in Accessibility, then Return pastes for you", symbol: "hand.raised")
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

    /// Deletes what was copied (or pasted) in the last 5 minutes; pinned cards stay.
    @objc private func forgetRecent() {
        store.deleteRecent(since: Date().addingTimeInterval(-300))
        reload()
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

extension AppDelegate: NSDraggingSource {
    /// Cards dragged out are copied: the shelf keeps them.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
