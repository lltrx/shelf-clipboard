import Carbon

/// Global shortcut via Carbon's RegisterEventHotKey (needs no Accessibility permission).
final class HotKey {
    private static var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    let display: String

    /// Spec like "cmd+option+v". Falls back to ⇧⌘V if it cannot be parsed.
    init?(spec: String, handler: @escaping () -> Void) {
        guard let (code, mods, display) = HotKey.parse(spec) ?? HotKey.parse("cmd+shift+v") else { return nil }
        self.display = display
        HotKey.handler = handler

        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.handler?()
            return noErr
        }, 1, &event, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x5348_4C46), id: 1) // "SHLF"
        guard RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "space": 49,
    ]

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
