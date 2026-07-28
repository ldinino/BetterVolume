import AppKit
import AudioRouting

/// Owns the menu bar item: left click switches output, right click opens the device menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let hud = OutputHUD()
    private lazy var preferences = PreferencesWindowController(model: model)

    init(model: AppModel) {
        self.model = model
        super.init()
        configureButton()
        model.onChange = { [weak self] in self?.updateButton() }
        model.onHotKey = { [weak self] in self?.toggleOutput() }
        model.onOutputChanged = { [weak self] device in
            self?.hud.show(symbolName: DeviceSymbol.name(for: device),
                           title: device.displayName)
        }
        updateButton()
    }

    // MARK: - Setup

    private func configureButton() {
        statusItem.autosaveName = "\(AppInfo.bundleIdentifier).statusItem"
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Click handling

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else {
            toggleOutput()
        }
    }

    private func toggleOutput() {
        model.refresh()
        guard model.toggleTarget != nil else {
            NSSound.beep()
            return
        }
        model.toggle()
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.activate(id: id)
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        preferences.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: AppInfo.credits])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Menu

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let volumeItem = NSMenuItem()
        volumeItem.view = VolumeMenuItemView(control: model.volumeControl) { [weak self] value in
            self?.model.setVolume(value)
        }
        menu.addItem(volumeItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if model.menuDevices.isEmpty {
            let empty = NSMenuItem(title: "No output devices", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for device in model.menuDevices {
            let item = NSMenuItem(title: device.displayName,
                                  action: #selector(selectDevice(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            item.state = device.isCurrent ? NSControl.StateValue.on : .off
            item.image = DeviceSymbol.image(named: DeviceSymbol.name(for: device),
                                            description: device.displayName,
                                            pointSize: 13)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func showMenu() {
        model.refresh()
        // Assign, click, unassign: this is the only way to get correct highlighting and
        // dismissal while keeping the left click free for an action.
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Rendering

    private func updateButton() {
        guard let button = statusItem.button else { return }
        guard let current = model.currentDevice else {
            button.image = DeviceSymbol.statusItemImage(named: "speaker.slash",
                                                        description: "No output device")
            button.toolTip = "\(AppInfo.name) — no audio output"
            return
        }
        button.image = DeviceSymbol.statusItemImage(named: DeviceSymbol.name(for: current),
                                                    description: current.displayName)
        button.toolTip = model.toggleTarget.map {
            "Output: \(current.displayName)\nClick to switch to \($0.displayName)"
        } ?? "Output: \(current.displayName)"
    }
}
