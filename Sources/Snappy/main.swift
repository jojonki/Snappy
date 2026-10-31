import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeys()
    private let drag = DragSnapper()
    private var dragItem: NSMenuItem!
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = WindowManager.isTrusted(prompt: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Snappy")

        buildMenu()
        registerHotKeys()
        NotificationCenter.default.addObserver(forName: ShortcutStore.changed, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKeys(); self?.buildMenu()
        }
        drag.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Updater.shared.checkIfDue() }
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        for zone in SnapZone.allCases {
            let s = ShortcutStore.get(zone)
            hotKeys.register(keyCode: s.keyCode, modifiers: s.modifiers) { WindowManager.snapFocusedWindow(to: zone) }
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        for zone in SnapZone.allCases {
            let item = NSMenuItem(title: "\(zone.title)    \(ShortcutStore.get(zone).display)", action: #selector(menuSnap(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = zone
            menu.addItem(item)
        }
        menu.addItem(.separator())
        dragItem = NSMenuItem(title: "Snap on Drag", action: #selector(toggleDrag), keyEquivalent: "")
        dragItem.target = self
        dragItem.state = drag.enabled ? .on : .off
        menu.addItem(dragItem)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self; menu.addItem(prefs)
        let upd = NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
        upd.target = self; menu.addItem(upd)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snappy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuSnap(_ sender: NSMenuItem) {
        if let zone = sender.representedObject as? SnapZone { WindowManager.snapFocusedWindow(to: zone) }
    }
    @objc private func toggleDrag() {
        drag.enabled.toggle()
        dragItem.state = drag.enabled ? .on : .off
    }
    @objc private func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.present()
    }
    @objc private func checkUpdates() { Updater.shared.check(userInitiated: true) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
