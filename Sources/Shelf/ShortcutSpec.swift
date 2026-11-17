import Foundation

/// A global shortcut as Settings stores it: "cmd+shift+v". It needs ⌘, ⌥ or ⌃ (⇧ and a letter
/// alone is just typing a capital). Foundation only, so it can be unit tested; HotKey registers it
/// with the system.
struct ShortcutSpec: Equatable {
    var key: String          // "v", "space"
    var command = false
    var option = false
    var shift = false
    var control = false

    /// The physical key codes (the key's place on the keyboard, whatever the layout) of the keys a
    /// shortcut can use.
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "space": 49,
    ]

    init?(key: String, command: Bool = false, option: Bool = false, shift: Bool = false, control: Bool = false) {
        guard Self.keyCodes[key] != nil, command || option || control else { return nil }
        self.key = key
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
    }

    /// A key pressed with these modifiers, as Settings records it.
    init?(keyCode: UInt16, command: Bool, option: Bool, shift: Bool, control: Bool) {
        guard let key = Self.keyCodes.first(where: { $0.value == keyCode })?.key else { return nil }
        self.init(key: key, command: command, option: option, shift: shift, control: control)
    }

    /// "cmd+option+v" (any order, any case; "command", "opt", "alt" and "control" work too).
    init?(_ spec: String) {
        var command = false, option = false, shift = false, control = false
        var key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "ctrl", "control": control = true
            case "option", "opt", "alt": option = true
            case "shift": shift = true
            case "cmd", "command": command = true
            default:
                guard key == nil else { return nil }   // two keys
                key = part
            }
        }
        guard let key else { return nil }
        self.init(key: key, command: command, option: option, shift: shift, control: control)
    }

    var keyCode: UInt16 { Self.keyCodes[key] ?? 0 }

    /// What's stored: "ctrl+option+shift+cmd+v", modifiers in the order the Mac shows them.
    var spec: String {
        [control ? "ctrl" : nil, option ? "option" : nil, shift ? "shift" : nil, command ? "cmd" : nil, key]
            .compactMap { $0 }
            .joined(separator: "+")
    }

    /// "⌥⇧⌘V"
    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
            + (key == "space" ? "Space" : key.uppercased())
    }
}
