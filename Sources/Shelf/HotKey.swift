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

    /// Spec like "cmd+option+v" (see ShortcutSpec). Nil if it can't be parsed or another app
    /// already has the shortcut.
    init?(spec: String, handler: @escaping () -> Void) {
        guard let shortcut = ShortcutSpec(spec) else { return nil }
        display = shortcut.display
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.installHandler()
        var mods: UInt32 = 0
        if shortcut.command { mods |= UInt32(cmdKey) }
        if shortcut.option { mods |= UInt32(optionKey) }
        if shortcut.shift { mods |= UInt32(shiftKey) }
        if shortcut.control { mods |= UInt32(controlKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_4C46), id: id)   // "SHLF"
        guard RegisterEventHotKey(UInt32(shortcut.keyCode), mods, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              ref != nil else { return nil }
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

    static func isValid(_ spec: String) -> Bool { ShortcutSpec(spec) != nil }

    /// "⇧⌘V" for "cmd+shift+v", or nil if it isn't a usable shortcut.
    static func display(_ spec: String) -> String? { ShortcutSpec(spec)?.display }
}
