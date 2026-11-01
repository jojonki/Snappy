import AppKit
import ApplicationServices

enum WindowManager {
    static func isTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Coordinate conversion (AX: top-left origin of primary screen; AppKit: bottom-left)
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAppKit(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func toAX(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: AX helpers
    static func focusedWindow() -> AXUIElement? {
        _ = systemWide  // ensure the global AX messaging timeout is applied
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
        return (value as! AXUIElement)
    }

    /// Shared system-wide element. Its messaging timeout becomes the default for all AX calls,
    /// so an unresponsive app can't block our main thread for the system default (~6 s).
    private static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 1.0)
        return el
    }()

    /// Window under a point (AppKit coordinates), via the AX hit-test.
    static func window(at appKitPoint: NSPoint) -> AXUIElement? {
        let p = CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success,
              var cur = el else { return nil }
        if role(of: cur) == kAXWindowRole as String { return cur }
        // Most elements expose their window directly: one IPC call instead of walking parents.
        var win: CFTypeRef?
        if AXUIElementCopyAttributeValue(cur, kAXWindowAttribute as CFString, &win) == .success,
           let win, CFGetTypeID(win) == AXUIElementGetTypeID() {
            return (win as! AXUIElement)
        }
        for _ in 0..<12 {
            if role(of: cur) == kAXWindowRole as String { return cur }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &parent) == .success else { return nil }
            cur = parent as! AXUIElement
        }
        return nil
    }

    static func role(of el: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static let frameAttributes = [kAXPositionAttribute, kAXSizeAttribute] as CFArray

    /// Position and size fetched in a single AX round-trip.
    static func frame(of window: AXUIElement) -> NSRect? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, frameAttributes, AXCopyMultipleAttributeOptions(), &values) == .success,
              let arr = values as? [AnyObject], arr.count == 2,
              CFGetTypeID(arr[0]) == AXValueGetTypeID(), CFGetTypeID(arr[1]) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        // AXValueGetValue fails if a slot holds an error value instead of the expected type.
        guard AXValueGetValue(arr[0] as! AXValue, .cgPoint, &pos),
              AXValueGetValue(arr[1] as! AXValue, .cgSize, &size) else { return nil }
        return toAppKit(CGRect(origin: pos, size: size))
    }

    static func setFrame(_ window: AXUIElement, to appKitFrame: NSRect, anchoredRight: Bool = false) {
        var r = toAX(appKitFrame)
        // Size first, then position, then size again (some apps clamp size based on position).
        func setSize() {
            if let v = AXValueCreate(.cgSize, &r.size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
            }
        }
        setSize()
        if let v = AXValueCreate(.cgPoint, &r.origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
        }
        setSize()

        // Some apps enforce a minimum size larger than requested. Read back the real size
        // and keep the intended edge anchored so the window stays on-screen and flush.
        if anchoredRight, let actual = frame(of: window), abs(actual.width - appKitFrame.width) > 1 {
            var origin = toAX(NSRect(x: appKitFrame.maxX - actual.width, y: appKitFrame.minY,
                                     width: actual.width, height: actual.height)).origin
            if let v = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
        }
    }

    static func screen(containing rect: NSRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    // MARK: Snapping
    static func snapFocusedWindow(to zone: SnapZone) {
        guard isTrusted(prompt: false), let win = focusedWindow(), let f = frame(of: win),
              let screen = screen(containing: f) else { return }
        setFrame(win, to: zone.frame(in: screen.visibleFrame), anchoredRight: zone == .right)
    }

    static func hideFrontmostApp() {
        NSWorkspace.shared.frontmostApplication?.hide()
    }

    static func snap(_ window: AXUIElement, to zone: SnapZone, on screen: NSScreen) {
        setFrame(window, to: zone.frame(in: screen.visibleFrame), anchoredRight: zone == .right)
    }
}
