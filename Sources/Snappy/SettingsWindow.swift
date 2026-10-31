import AppKit

/// Button that records a key combo when clicked.
final class ShortcutRecorder: NSButton {
    var onChange: ((Shortcut) -> Void)?
    private var monitor: Any?
    var shortcut: Shortcut { didSet { title = shortcut.display } }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = shortcut.display
        target = self; action = #selector(toggle)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() { monitor == nil ? begin() : end() }

    private func begin() {
        title = "Press shortcut… (Esc to cancel)"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.end(); return nil }   // Esc
            let mods = Shortcut.carbonModifiers(from: e.modifierFlags.intersection(.deviceIndependentFlagsMask))
            guard mods != 0 else { NSSound.beep(); return nil }   // require a modifier
            let s = Shortcut(keyCode: Int(e.keyCode), modifiers: mods)
            self.shortcut = s
            self.end()
            self.onChange?(s)
            return nil
        }
    }

    private func end() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        title = shortcut.display
    }
}

final class SettingsWindowController: NSWindowController {
    private var recorders: [SnapZone: ShortcutRecorder] = [:]
    private let autoUpdate = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)

    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Snappy Settings"
        super.init(window: win)
        build()
        win.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let grid = NSGridView()
        grid.rowSpacing = 10; grid.columnSpacing = 12
        for zone in SnapZone.allCases {
            let r = ShortcutRecorder(shortcut: ShortcutStore.get(zone))
            r.onChange = { ShortcutStore.set($0, for: zone) }
            recorders[zone] = r
            r.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
            grid.addRow(with: [NSTextField(labelWithString: zone.title + ":"), r])
        }
        grid.column(at: 0).xPlacement = .trailing

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults))
        autoUpdate.state = Updater.autoCheckEnabled ? .on : .off
        autoUpdate.target = self; autoUpdate.action = #selector(toggleAuto)
        let check = NSButton(title: "Check for Updates Now", target: self, action: #selector(checkNow))
        let version = NSTextField(labelWithString: "Version \(Updater.currentVersion)")
        version.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [NSTextField(labelWithString: "Keyboard Shortcuts"), grid, reset,
                                        NSBox.separator(), autoUpdate, check, version])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window?.contentView = stack
        window?.setContentSize(stack.fittingSize)
    }

    @objc private func resetDefaults() {
        for zone in SnapZone.allCases {
            ShortcutStore.set(nil, for: zone)
            recorders[zone]?.shortcut = Shortcut.defaults[zone]!
        }
    }
    @objc private func toggleAuto() { Updater.autoCheckEnabled = autoUpdate.state == .on }
    @objc private func checkNow() { Updater.shared.check(userInitiated: true) }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}

extension NSBox {
    static func separator() -> NSBox {
        let b = NSBox(); b.boxType = .separator
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        return b
    }
}
