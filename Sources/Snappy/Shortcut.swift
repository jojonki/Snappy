import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int   // Carbon modifier mask

    static let defaults: [SnapZone: Shortcut] = {
        let m = controlKey | optionKey
        return [.left: Shortcut(keyCode: kVK_LeftArrow, modifiers: m),
                .right: Shortcut(keyCode: kVK_RightArrow, modifiers: m),
                .full: Shortcut(keyCode: kVK_UpArrow, modifiers: m)]
    }()

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return m
    }

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    private static func keyName(_ code: Int) -> String {
        let special: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Space: "Space", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ANSI_KeypadEnter: "⌤", kVK_Home: "Home", kVK_End: "End",
            kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        ]
        if let s = special[code] { return s }
        if code >= kVK_F1, let f = [kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6,
                                     kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12][code] {
            return "F\(f)"
        }
        // Translate through the current keyboard layout.
        if let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let ok = data.withUnsafeBytes { raw -> Bool in
                let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
                return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                      UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                      &dead, 4, &len, &chars) == noErr
            }
            if ok, len > 0 { return String(utf16CodeUnits: chars, count: len).uppercased() }
        }
        return "Key\(code)"
    }
}

enum ShortcutStore {
    static let changed = Notification.Name("ShortcutsChanged")

    static func get(_ zone: SnapZone) -> Shortcut {
        if let d = UserDefaults.standard.data(forKey: "shortcut.\(zone.id)"),
           let s = try? JSONDecoder().decode(Shortcut.self, from: d) { return s }
        return Shortcut.defaults[zone]!
    }
    static func set(_ s: Shortcut?, for zone: SnapZone) {
        if let s, let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: "shortcut.\(zone.id)")
        } else {
            UserDefaults.standard.removeObject(forKey: "shortcut.\(zone.id)")
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
