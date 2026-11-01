import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int   // Carbon modifier mask

    /// Default shortcuts; actions absent here (e.g. hide) are unassigned by default.
    static let defaults: [ShortcutAction: Shortcut] = {
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

    private static let specialKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Space: "Space", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ANSI_KeypadEnter: "⌤", kVK_Home: "Home", kVK_End: "End",
            kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, code) in fKeys.enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()

    private static func keyName(_ code: Int) -> String {
        if let s = specialKeyNames[code] { return s }
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

enum ShortcutAction: CaseIterable {
    case left, right, full, hide

    var id: String {
        switch self { case .left: return "left"; case .right: return "right"; case .full: return "full"; case .hide: return "hide" }
    }
    var title: String {
        switch self {
        case .left: return SnapZone.left.title
        case .right: return SnapZone.right.title
        case .full: return SnapZone.full.title
        case .hide: return "Hide App"
        }
    }
    var zone: SnapZone? {
        switch self { case .left: return .left; case .right: return .right; case .full: return .full; case .hide: return nil }
    }

    func perform() {
        if let zone { WindowManager.snapFocusedWindow(to: zone) }
        else { WindowManager.hideFrontmostApp() }
    }
}

enum ShortcutStore {
    static let changed = Notification.Name("ShortcutsChanged")

    private static func disabledKey(_ a: ShortcutAction) -> String { "shortcut.\(a.id).disabled" }

    /// nil = no key assigned (disabled).
    static func get(_ a: ShortcutAction) -> Shortcut? {
        let ud = UserDefaults.standard
        if ud.bool(forKey: disabledKey(a)) { return nil }
        if let d = ud.data(forKey: "shortcut.\(a.id)"),
           let s = try? JSONDecoder().decode(Shortcut.self, from: d) { return s }
        return Shortcut.defaults[a]
    }

    /// Pass nil to disable the action (no key assigned).
    static func set(_ s: Shortcut?, for a: ShortcutAction) {
        let ud = UserDefaults.standard
        if let s, let d = try? JSONEncoder().encode(s) {
            ud.set(d, forKey: "shortcut.\(a.id)")
            ud.removeObject(forKey: disabledKey(a))
        } else {
            ud.removeObject(forKey: "shortcut.\(a.id)")
            ud.set(true, forKey: disabledKey(a))
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Restores every action's default, posting a single change notification
    /// (each notification re-registers all hotkeys and rebuilds the menu).
    static func resetAll() {
        for a in ShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: "shortcut.\(a.id)")
            UserDefaults.standard.removeObject(forKey: disabledKey(a))
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
