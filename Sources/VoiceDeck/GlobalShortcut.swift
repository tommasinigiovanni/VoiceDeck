import Carbon

/// Carbon hot keys work while another app is active, without monitoring arbitrary keyboard input.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var isDown = false
    var onPress: (() -> Void)?
    static let choices = ["controlOptionSpace", "commandShiftSpace", "controlOptionR", "disabled"]
    static func title(_ key: String) -> String {
        switch key {
        case "commandShiftSpace": return "⌘⇧Spazio"
        case "controlOptionR": return "⌃⌥R"
        case "disabled": return "Disattivata"
        default: return "⌃⌥Spazio"
        }
    }

    init() {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x5644434B, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { shortcut.isDown = false }
                else if !shortcut.isDown { shortcut.isDown = true; shortcut.onPress?() }
            }
            return noErr
        }, 2, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ choice: String) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil
        isDown = false
        guard choice != "disabled" else { return true }
        guard handler != nil else { return false }
        let key: UInt32 = choice == "controlOptionR" ? UInt32(kVK_ANSI_R) : UInt32(kVK_Space)
        let modifiers = choice == "commandShiftSpace" ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey)
        let id = EventHotKeyID(signature: 0x5644434B, id: 1)
        return RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
