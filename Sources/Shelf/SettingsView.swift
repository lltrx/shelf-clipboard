import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// What Settings needs from the app.
protocol SettingsActions: AnyObject {
    /// Registers the shortcuts saved in Settings and says which ones worked (another app may
    /// already have one).
    func applyShortcuts() -> (open: Bool, previous: Bool)
    /// While a shortcut is being recorded, the current ones are let go, so pressing them records them.
    func pauseShortcuts()
    /// Something else in Settings changed: pick it up.
    func settingsChanged()
}

/// The Settings window's state. Values live in UserDefaults (the same keys the app reads), so the
/// window always shows what's in effect, even if a menu changed it meanwhile.
final class SettingsModel: ObservableObject {
    enum Shortcut { case open, previous }

    weak var actions: SettingsActions?
    @Published private(set) var recording: Shortcut?
    @Published var shortcutMessage: String?
    @Published var loginMessage: String?
    private let defaults = UserDefaults.standard
    private var keyMonitor: Any?
    private var observer: Any?

    static let defaultOpen = "cmd+shift+v"
    static let defaultPrevious = "cmd+option+shift+v"
    static let historyChoices = [7, 14, 30, 90, 365, 0]
    static let secretChoices: [Double] = [1, 5, 15, 60, 0]

    init() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func set(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        actions?.settingsChanged()
    }

    // MARK: Shortcuts

    private func key(_ shortcut: Shortcut) -> String { shortcut == .open ? "hotkey" : "pastePreviousHotkey" }

    private func fallback(_ shortcut: Shortcut) -> String { shortcut == .open ? Self.defaultOpen : Self.defaultPrevious }

    /// The shortcut in effect, or nil when Paste Previous is turned off.
    func spec(_ shortcut: Shortcut) -> ShortcutSpec? {
        let stored = defaults.string(forKey: key(shortcut)) ?? fallback(shortcut)
        if shortcut == .previous && stored.isEmpty { return nil }
        return ShortcutSpec(stored) ?? ShortcutSpec(fallback(shortcut))
    }

    func isDefault(_ shortcut: Shortcut) -> Bool { spec(shortcut) == ShortcutSpec(fallback(shortcut)) }

    func startRecording(_ shortcut: Shortcut) {
        stopRecording()
        recording = shortcut
        shortcutMessage = "Press the new shortcut, or Esc to keep the old one."
        actions?.pauseShortcuts()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let shortcut = self.recording else { return event }
            self.record(event, for: shortcut)
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard recording != nil else { return }
        recording = nil
        shortcutMessage = nil
        _ = actions?.applyShortcuts()
    }

    private func record(_ event: NSEvent, for shortcut: Shortcut) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { stopRecording(); return }                                    // esc
        if (event.keyCode == 51 || event.keyCode == 117), flags.intersection([.command, .option, .control]).isEmpty {
            stopRecording()                                                                   // ⌫
            if shortcut == .previous { turnOffPrevious() } else { reset(.open) }
            return
        }
        guard let new = ShortcutSpec(keyCode: event.keyCode, command: flags.contains(.command), option: flags.contains(.option),
                                     shift: flags.contains(.shift), control: flags.contains(.control)) else {
            NSSound.beep()
            shortcutMessage = "Use ⌘, ⌥ or ⌃ with a letter, a number or Space."
            return
        }
        let other: Shortcut = shortcut == .open ? .previous : .open
        if spec(other) == new {
            NSSound.beep()
            shortcutMessage = "\(new.display) is already \(other == .open ? "Open Shelf" : "Paste Previous Copy")."
            return
        }
        let old = defaults.string(forKey: key(shortcut))
        defaults.set(new.spec, forKey: key(shortcut))
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recording = nil
        let worked = actions?.applyShortcuts() ?? (open: true, previous: true)
        if !(shortcut == .open ? worked.open : worked.previous) {
            defaults.set(old, forKey: key(shortcut))   // put back the one that worked
            _ = actions?.applyShortcuts()
            shortcutMessage = "Another app already uses \(new.display). Try a different one."
        } else {
            shortcutMessage = nil
        }
    }

    func reset(_ shortcut: Shortcut) {
        stopRecording()
        defaults.removeObject(forKey: key(shortcut))
        let worked = actions?.applyShortcuts() ?? (open: true, previous: true)
        let ok = shortcut == .open ? worked.open : worked.previous
        shortcutMessage = ok ? nil : "Another app already uses \(ShortcutSpec(fallback(shortcut))?.display ?? "it")."
    }

    func turnOffPrevious() {
        stopRecording()
        defaults.set("", forKey: key(.previous))
        _ = actions?.applyShortcuts()
        shortcutMessage = nil
    }

    // MARK: Pasting

    var plainByDefault: Bool {
        get { defaults.bool(forKey: "pastePlainByDefault") }
        set { set(newValue, "pastePlainByDefault") }
    }

    var askBeforePasting: Bool {
        get { defaults.object(forKey: "askBeforePasting") as? Bool ?? true }
        set { set(newValue, "askBeforePasting") }
    }

    struct AppStyle: Identifiable {
        let bundle: String
        let name: String
        let plain: Bool
        var id: String { bundle }
    }

    /// The apps whose paste style isn't the default.
    var appStyles: [AppStyle] {
        let styles = defaults.dictionary(forKey: "pasteStyleByApp") as? [String: Bool] ?? [:]
        return styles.map { AppStyle(bundle: $0.key, name: AppDelegate.appName($0.key), plain: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func forgetStyle(_ bundle: String) {
        var styles = defaults.dictionary(forKey: "pasteStyleByApp") as? [String: Bool] ?? [:]
        styles[bundle] = nil
        set(styles, "pasteStyleByApp")
    }

    // MARK: History

    var historyDays: Int {
        get { defaults.object(forKey: "historyDays") as? Int ?? 30 }
        set { set(newValue, "historyDays") }
    }

    var secretMinutes: Double {
        get { defaults.object(forKey: "secretMinutes") as? Double ?? 5 }
        set { set(newValue, "secretMinutes") }
    }

    var addScreenshots: Bool {
        get { defaults.object(forKey: "addScreenshots") as? Bool ?? true }
        set { set(newValue, "addScreenshots") }
    }

    struct App: Identifiable {
        let bundle: String
        let name: String
        var id: String { bundle }
    }

    var ignoredApps: [App] {
        (defaults.stringArray(forKey: "ignoredApps") ?? []).map { App(bundle: $0, name: AppDelegate.appName($0)) }
    }

    func stopIgnoring(_ bundle: String) {
        set((defaults.stringArray(forKey: "ignoredApps") ?? []).filter { $0 != bundle }, "ignoredApps")
    }

    func addIgnoredApp(in window: NSWindow?) {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.application]
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.prompt = "Ignore"
        open.message = "Shelf won't record anything copied in this app."
        let add: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = open.url, let bundle = Bundle(url: url)?.bundleIdentifier else { return }
            var apps = self.defaults.stringArray(forKey: "ignoredApps") ?? []
            guard !apps.contains(bundle) else { return }
            apps.append(bundle)
            self.set(apps, "ignoredApps")
        }
        if let window { open.beginSheetModal(for: window, completionHandler: add) } else { add(open.runModal()) }
    }

    // MARK: General

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginMessage = nil
            } catch {
                loginMessage = error.localizedDescription
            }
            objectWillChange.send()
        }
    }

    var canAutoPaste: Bool { AXIsProcessTrusted() }

    func allowAutoPaste() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func refresh() { objectWillChange.send() }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Shortcuts") {
                shortcutRow("Open Shelf", .open)
                shortcutRow("Paste previous copy", .previous,
                            note: "Pastes the copy before the last one, without opening the shelf. Press it again to swap back.")
                if let message = settings.shortcutMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Pasting") {
                Picker("Return pastes", selection: binding(\.plainByDefault)) {
                    Text("With formatting").tag(false)
                    Text("Plain text").tag(true)
                }
                .help("⇧Return pastes the other way")
                if !settings.appStyles.isEmpty {
                    ForEach(settings.appStyles) { style in
                        LabeledContent {
                            HStack(spacing: 8) {
                                Text(style.plain ? "Plain text" : "With formatting").foregroundStyle(.secondary)
                                removeButton("Use the default in \(style.name)") { settings.forgetStyle(style.bundle) }
                            }
                        } label: {
                            Text(style.name).padding(.leading, 12)
                        }
                    }
                }
                Text("To paste differently in one app, open the shelf there and choose at its bottom right.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Ask before pasting images and files", isOn: binding(\.askBeforePasting))
                    .help("Return opens a small box to rename, resize, convert, blur or crop first; ⇧Return pastes right away")
                LabeledContent("Auto-paste") {
                    if settings.canAutoPaste {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { settings.allowAutoPaste() }
                    }
                }
                .help("Lets Shelf press ⌘V for you after you pick a card (System Settings → Privacy & Security → Accessibility)")
            }

            Section("History") {
                Picker("Keep history for", selection: binding(\.historyDays)) {
                    ForEach(SettingsModel.historyChoices, id: \.self) { days in
                        Text(historyTitle(days)).tag(days)
                    }
                }
                .help("Pinned cards are kept until you delete them")
                Picker("Delete passwords and keys after", selection: binding(\.secretMinutes)) {
                    ForEach(SettingsModel.secretChoices, id: \.self) { minutes in
                        Text(secretTitle(minutes)).tag(minutes)
                    }
                }
                .help("Copies that look like API keys, tokens, passwords or card numbers are hidden on their cards and deleted after this long, unless you pin them")
                Toggle("Add screenshots", isOn: binding(\.addScreenshots))
                    .help("Screenshots saved as files (⇧⌘3, ⇧⌘4, ⇧⌘5) appear in the shelf, ready to paste")
            }

            Section {
                if settings.ignoredApps.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredApps) { app in
                    LabeledContent(app.name) {
                        removeButton("Record copies from \(app.name) again") { settings.stopIgnoring(app.bundle) }
                    }
                }
                Button("Add App…") { settings.addIgnoredApp(in: NSApp.keyWindow) }
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Nothing copied in these apps is recorded. Password managers are always skipped.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: binding(\.launchAtLogin))
                if let message = settings.loginMessage {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refresh()   // Auto-paste may have been allowed in System Settings meanwhile
        }
    }

    private func shortcutRow(_ title: String, _ shortcut: SettingsModel.Shortcut, note: String? = nil) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                let recording = settings.recording == shortcut
                Button { recording ? settings.stopRecording() : settings.startRecording(shortcut) } label: {
                    Text(recording ? "Type shortcut…" : settings.spec(shortcut)?.display ?? "Off")
                        .font(.system(size: 12.5, weight: recording ? .regular : .medium))
                        .foregroundStyle(recording ? Color.accentColor : Color.primary)
                        .frame(minWidth: 110)
                }
                .help("Click, then press the new shortcut. ⌫ \(shortcut == .previous ? "turns it off" : "goes back to ⇧⌘V").")
                if !settings.isDefault(shortcut) && !recording {
                    Button { settings.reset(shortcut) } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .help("Back to \(ShortcutSpec(shortcut == .open ? SettingsModel.defaultOpen : SettingsModel.defaultPrevious)?.display ?? "the default")")
                }
                if shortcut == .previous && settings.spec(.previous) != nil && !recording {
                    removeButton("Turn off") { settings.turnOffPrevious() }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private func removeButton(_ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func binding<T>(_ key: ReferenceWritableKeyPath<SettingsModel, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: key] }, set: { settings[keyPath: key] = $0 })
    }

    private func historyTitle(_ days: Int) -> String {
        switch days {
        case 0: return "Forever"
        case 7: return "1 week"
        case 14: return "2 weeks"
        case 30: return "1 month"
        case 90: return "3 months"
        case 365: return "1 year"
        default: return "\(days) days"
        }
    }

    private func secretTitle(_ minutes: Double) -> String {
        switch minutes {
        case 0: return "Never (keep them like other copies)"
        case 1: return "1 minute"
        case 60: return "1 hour"
        default: return "\(Int(minutes)) minutes"
        }
    }
}
