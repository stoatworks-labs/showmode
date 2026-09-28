import Carbon

/// System-wide hotkeys via Carbon's RegisterEventHotKey — works from a background app and
/// needs no Accessibility or Input Monitoring permission.
final class Hotkeys {
    static let shared = Hotkeys()
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    /// ⌃⌥⌘ plus a key code.
    func register(keyCode: Int, _ action: @escaping () -> Void) {
        installHandler()
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x5348_4F57), id: id) // 'SHOW'
        let mods = UInt32(controlKey | optionKey | cmdKey)
        if RegisterEventHotKey(UInt32(keyCode), mods, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { Hotkeys.shared.actions[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
