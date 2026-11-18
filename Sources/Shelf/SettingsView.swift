import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// An app's name from its bundle id ("Slack" for com.tinyspeck.slackmacgap), or the id if it isn't installed.
enum AppName {
    static func of(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// What Settings needs from the app.
protocol SettingsActions: AnyObject {
    /// Registers the shortcuts saved in Settings and returns the ones that didn't work (another app
    /// already has those keys).
    func applyShortcuts() -> Set<GlobalShortcut>
    /// While a shortcut is being recorded, the current ones are let go, so pressing them records them.
    func pauseShortcuts()
    /// Something else in Settings changed: pick it up.
    func settingsChanged()
    /// Removes Shelf's old Accessibility entry and asks macOS again (see AppDelegate.fixAutoPaste).
    func fixAutoPaste()
}

/// The Settings window's state. Values live in UserDefaults (the same keys the app reads), so the
/// window always shows what's in effect, even if a menu changed it meanwhile. It uses no AppKit
/// windows or events itself: the app's key monitor hands it the keys while a shortcut is recorded.
final class SettingsModel: ObservableObject {
    typealias Shortcut = GlobalShortcut

    weak var actions: SettingsActions?
    @Published private(set) var recording: Shortcut?
    @Published var shortcutMessage: String?
    @Published var loginMessage: String?
    private let defaults = UserDefaults.standard
    private var observer: Any?

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

    /// The shortcut in effect, or nil when it's turned off.
    func spec(_ shortcut: Shortcut) -> ShortcutSpec? { shortcut.spec(stored: defaults.string(forKey: shortcut.key)) }

    func isDefault(_ shortcut: Shortcut) -> Bool { spec(shortcut) == ShortcutSpec(shortcut.fallback) }

    func startRecording(_ shortcut: Shortcut) {
        stopRecording()
        recording = shortcut
        shortcutMessage = "Press the new shortcut, or Esc to keep the old one."
        actions?.pauseShortcuts()
    }

    /// Esc, clicking the button again, closing Settings or switching away: the shortcuts as they were.
    func stopRecording() {
        guard recording != nil else { return }
        recording = nil
        shortcutMessage = nil
        _ = actions?.applyShortcuts()
    }

    /// A key pressed while recording. False when it can't be used (the app beeps).
    func record(keyCode: UInt16, command: Bool, option: Bool, shift: Bool, control: Bool) -> Bool {
        guard let shortcut = recording else { return true }
        if keyCode == 53 { stopRecording(); return true }                                    // esc
        if keyCode == 51 || keyCode == 117, !command, !option, !control {                    // ⌫
            stopRecording()
            if shortcut.canTurnOff { turnOff(shortcut) } else { reset(shortcut) }
            return true
        }
        guard let new = ShortcutSpec(keyCode: keyCode, command: command, option: option, shift: shift, control: control) else {
            shortcutMessage = "Use ⌘, ⌥ or ⌃ with a letter, a number or Space."
            return false
        }
        if let other = Shortcut.allCases.first(where: { $0 != shortcut && spec($0) == new }) {
            shortcutMessage = "\(new.display) is already \(other.title)."
            return false
        }
        let old = defaults.string(forKey: shortcut.key)
        defaults.set(new.spec, forKey: shortcut.key)
        recording = nil
        if actions?.applyShortcuts().contains(shortcut) == true {
            defaults.set(old, forKey: shortcut.key)   // put back the one that worked
            _ = actions?.applyShortcuts()
            shortcutMessage = "Another app already uses \(new.display). Try a different one."
        } else {
            shortcutMessage = nil
        }
        return true
    }

    func reset(_ shortcut: Shortcut) {
        stopRecording()
        defaults.removeObject(forKey: shortcut.key)
        let failed = actions?.applyShortcuts().contains(shortcut) == true
        shortcutMessage = failed ? "Another app already uses \(ShortcutSpec(shortcut.fallback)?.display ?? "it")." : nil
    }

    func turnOff(_ shortcut: Shortcut) {
        guard shortcut.canTurnOff else { return }
        stopRecording()
        defaults.set("", forKey: shortcut.key)
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

    var cleanLinks: Bool {
        get { defaults.object(forKey: "cleanLinks") as? Bool ?? true }
        set { set(newValue, "cleanLinks") }
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
        return styles.map { AppStyle(bundle: $0.key, name: AppName.of($0.key), plain: $0.value) }
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

    struct IgnoredApp: Identifiable {
        let bundle: String
        let name: String
        var id: String { bundle }
    }

    var ignoredApps: [IgnoredApp] {
        (defaults.stringArray(forKey: "ignoredApps") ?? []).map { IgnoredApp(bundle: $0, name: AppName.of($0)) }
    }

    func stopIgnoring(_ bundle: String) {
        set((defaults.stringArray(forKey: "ignoredApps") ?? []).filter { $0 != bundle }, "ignoredApps")
    }

    func ignore(_ bundle: String) {
        var apps = defaults.stringArray(forKey: "ignoredApps") ?? []
        guard !apps.contains(bundle) else { return }
        apps.append(bundle)
        set(apps, "ignoredApps")
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

    var canCaptureScreen: Bool { CGPreflightScreenCaptureAccess() }

    func allowScreenCapture() { _ = Self.askForScreenCapture() }

    /// The first time, asks macOS, which shows its own prompt. After that (macOS asks only once), opens
    /// the Screen Recording settings and returns true. (The request answers false right away, even
    /// while its prompt is up, so whether it was asked is remembered.)
    static func askForScreenCapture() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "askedScreenCapture") else {
            defaults.set(true, forKey: "askedScreenCapture")
            _ = CGRequestScreenCaptureAccess()
            return false
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    func allowAutoPaste() { actions?.fixAutoPaste() }

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
                shortcutRow("Grab text from screen", .grabText,
                            note: "Drag over anything on screen; the text in it is copied, ready to paste.")
                LabeledContent("Screen Recording") {
                    if settings.canCaptureScreen {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { settings.allowScreenCapture() }
                    }
                }
                .help("Grab Text from Screen needs it to see other apps' windows (System Settings → Privacy & Security → Screen & System Audio Recording)")
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
                Toggle("Remove tracking from copied links", isOn: binding(\.cleanLinks))
                    .help("utm_…, fbclid, gclid and similar are removed as you copy a link, from its card and from the clipboard")
                Toggle("Ask before pasting images and files", isOn: binding(\.askBeforePasting))
                    .help("Return opens a small box to rename, resize, convert, blur or crop first; ⇧Return pastes right away")
                LabeledContent("Auto-paste") {
                    if settings.canAutoPaste {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Turn On…") { settings.allowAutoPaste() }
                    }
                }
                .help("Lets Shelf press ⌘V for you after you pick a card (System Settings → Privacy & Security → Accessibility). Turn On also clears an old Shelf entry that looks on but no longer counts.")
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
                Button("Add App…") {
                    let open = NSOpenPanel()
                    open.allowedContentTypes = [.application]
                    open.directoryURL = URL(fileURLWithPath: "/Applications")
                    open.prompt = "Ignore"
                    open.message = "Shelf won't record anything copied in this app."
                    if open.runModal() == .OK, let url = open.url, let bundle = Bundle(url: url)?.bundleIdentifier {
                        settings.ignore(bundle)
                    }
                }
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
                .help("Click, then press the new shortcut. ⌫ \(shortcut.canTurnOff ? "turns it off" : "goes back to the default").")
                if !settings.isDefault(shortcut) && !recording {
                    Button { settings.reset(shortcut) } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .help("Back to \(ShortcutSpec(shortcut.fallback)?.display ?? "the default")")
                }
                if shortcut.canTurnOff && settings.spec(shortcut) != nil && !recording {
                    removeButton("Turn off") { settings.turnOff(shortcut) }
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
