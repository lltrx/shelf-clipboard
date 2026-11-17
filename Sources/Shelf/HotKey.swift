import Carbon

/// A global shortcut via Carbon's RegisterEventHotKey (needs no Accessibility permission). Several
/// can be registered at once (open the shelf, paste the previous copy); one event handler, installed
/// once, calls the right one by id. Releasing a HotKey unregisters it, so Settings can change them live.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private let id: UInt32
    let display: String   // "⇧⌘V"

    /// Spec like "cmd+option+v". Nil if it can't be parsed or another app already has the shortcut.
    init?(spec: String, handler: @escaping () -> Void) {
        guard let (code, mods, display) = HotKey.parse(spec) else { return nil }
        self.display = display
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_4C46), id: id)   // "SHLF"
        guard RegisterEventHotKey(code, mods, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr { HotKey.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &event, nil, nil)
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "space": 49,
    ]

    /// The spec's name for a physical key ("v", "space"), or nil if shortcuts can't use it.
    static func keyName(for code: UInt16) -> String? {
        keyCodes.first { $0.value == UInt32(code) }?.key
    }

    static func isValid(_ spec: String) -> Bool { parse(spec) != nil }

    /// "⇧⌘V" for "cmd+shift+v", or nil if it isn't a usable shortcut.
    static func display(_ spec: String) -> String? { parse(spec)?.2 }

    private static func parse(_ spec: String) -> (UInt32, UInt32, String)? {
        var mods: UInt32 = 0
        var symbols = ""
        var key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "option", "opt", "alt": mods |= UInt32(optionKey)
            case "shift": mods |= UInt32(shiftKey)
            case "cmd", "command": mods |= UInt32(cmdKey)
            default: key = part
            }
        }
        guard let key, let code = keyCodes[key], mods != 0 else { return nil }
        if mods & UInt32(controlKey) != 0 { symbols += "⌃" }
        if mods & UInt32(optionKey) != 0 { symbols += "⌥" }
        if mods & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if mods & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return (code, mods, symbols + (key == "space" ? "Space" : key.uppercased()))
    }
}
