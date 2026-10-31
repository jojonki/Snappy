import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon (needs no extra permissions).
final class HotKeys {
    private var refs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let me = Unmanaged<HotKeys>.fromOpaque(userData!).takeUnretainedValue()
            me.actions[hkID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func unregisterAll() {
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        refs.removeAll(); actions.removeAll()
    }

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = nextID; nextID += 1
        actions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x534E5059), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}
