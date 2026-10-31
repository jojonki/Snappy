import AppKit
import ApplicationServices

/// Detects window drags toward screen edges, shows a preview overlay, and snaps on release.
final class DragSnapper {
    var enabled = true
    private var monitors: [Any] = []
    private var window: AXUIElement?
    private var startFrame: NSRect?
    private var moved = false
    private var currentZone: SnapZone?
    private var currentScreen: NSScreen?
    private let overlay = OverlayWindow()
    private let edge: CGFloat = 8       // px from edge triggering left/right
    private let topEdge: CGFloat = 8    // px from top triggering full

    func start() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.down() } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.drag() } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.up() } as Any)
    }

    private func down() {
        window = nil; startFrame = nil; moved = false; currentZone = nil
        guard enabled, WindowManager.isTrusted(prompt: false),
              let w = WindowManager.window(at: NSEvent.mouseLocation) else { return }
        window = w
        startFrame = WindowManager.frame(of: w)
    }

    private func drag() {
        guard enabled, let w = window, let start = startFrame else { return }
        if !moved {
            // Only treat as a window drag once the window actually moved (title-bar drag, not resize/content drag).
            guard let now = WindowManager.frame(of: w),
                  abs(now.minX - start.minX) > 2 || abs(now.minY - start.minY) > 2,
                  abs(now.width - start.width) < 1, abs(now.height - start.height) < 1 else { return }
            moved = true
        }
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) else { hide(); return }
        let f = screen.frame
        let zone: SnapZone?
        if p.y >= f.maxY - topEdge { zone = .full }
        else if p.x <= f.minX + edge { zone = .left }
        else if p.x >= f.maxX - edge { zone = .right }
        else { zone = nil }

        if let zone {
            if zone != currentZone || screen !== currentScreen {
                currentZone = zone; currentScreen = screen
                overlay.show(frame: zone.frame(in: screen.visibleFrame))
            }
        } else { hide() }
    }

    private func up() {
        defer { window = nil; startFrame = nil; moved = false; hide() }
        guard moved, let w = window, let zone = currentZone, let screen = currentScreen else { return }
        WindowManager.snap(w, to: zone, on: screen)
    }

    private func hide() {
        currentZone = nil; currentScreen = nil
        overlay.hide()
    }
}

final class OverlayWindow {
    private lazy var win: NSWindow = {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 10
        w.contentView = v
        return w
    }()

    func show(frame: NSRect) {
        win.setFrame(frame.insetBy(dx: 4, dy: 4), display: true)
        win.orderFrontRegardless()
    }
    func hide() { win.orderOut(nil) }
}
