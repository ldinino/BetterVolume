import AudioHAL
import AudioRouting
import Foundation
import Observation
/// Single source of truth for the menu bar item and the preferences window.
@MainActor
@Observable
final class AppModel {
    private(set) var settings: Settings
    private(set) var devices: [ResolvedDevice] = []
    /// True when the system refused the saved shortcut, i.e. another app already owns it.
    private(set) var isHotKeyRejected = false

    /// Called after any change so the AppKit status item can redraw.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// Called when the global shortcut is pressed. Wired to the same path as a left click.
    @ObservationIgnored var onHotKey: (@MainActor () -> Void)?
    /// Called after we switch the output ourselves, so the change can be shown on screen.
    @ObservationIgnored var onOutputChanged: (@MainActor (ResolvedDevice) -> Void)?

    @ObservationIgnored private let audio = HALAudioSystem()
    @ObservationIgnored private let hotKeys = GlobalHotKeyMonitor()
    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.load()
        audio.onChange = { [weak self] in self?.handleSystemChange() }
        audio.startObserving()
        hotKeys.action = { [weak self] in self?.onHotKey?() }
        syncHotKey()
        refresh()
        rememberCurrentDevice()
    }

    // MARK: - Derived state

    var menuDevices: [ResolvedDevice] {
        devices.filter { $0.isOnline && !$0.record.isHidden }
    }

    var currentDevice: ResolvedDevice? {
        devices.first(where: \.isCurrent)
    }

    var toggleTarget: ResolvedDevice? {
        ToggleResolver.target(settings: settings, devices: devices)
    }

    /// `nil` when the current output has no volume control at all.
    var volumeControl: VolumeControl? {
        guard let device = currentDevice?.device else { return nil }
        return audio.volumeControl(for: device)
    }

    func setVolume(_ value: Float) {
        guard let device = currentDevice?.device else { return }
        audio.setVolume(value, for: device)
    }

    // MARK: - Actions

    func toggle() {
        refresh()
        guard let target = toggleTarget else { return }
        activate(target)
    }

    @discardableResult
    func activate(_ target: ResolvedDevice) -> Bool {
        guard let device = target.device else { return false }
        do {
            try audio.setDefaultOutput(device)
            persist(settings.recordingUse(of: target.id))
            refresh()
            // Report the reconciled record, not the one we were handed, so the name and icon
            // are whatever the menu would show now.
            onOutputChanged?(devices.first { $0.id == target.id } ?? target)
            return true
        } catch {
            return false
        }
    }

    func activate(id: UUID) {
        guard let target = devices.first(where: { $0.id == id }) else { return }
        activate(target)
    }

    /// Re-reads the audio system and folds the result back into saved settings.
    func refresh() {
        let result = DeviceRegistry.reconcile(settings: settings,
                                              live: audio.outputDevices(),
                                              current: audio.defaultOutput())
        devices = result.devices
        persist(result.settings)
        onChange?()
    }

    // MARK: - Settings mutations

    /// Stored verbatim so nothing is eaten mid-typing — `displayName` does the trimming.
    func setAlias(_ alias: String, for id: UUID) {
        updateRecord(id: id) { $0.alias = alias.isEmpty ? nil : alias }
    }

    /// `nil` restores the automatic icon.
    func setSymbolName(_ symbolName: String?, for id: UUID) {
        updateRecord(id: id) { $0.symbolName = symbolName }
    }

    func setHidden(_ isHidden: Bool, for id: UUID) {
        updateRecord(id: id) { $0.isHidden = isHidden }
    }

    func moveDevices(fromOffsets source: IndexSet, toOffset destination: Int) {
        var copy = settings
        copy.devices.move(fromOffsets: source, toOffset: destination)
        persist(copy)
        refresh()
    }

    func setToggleMode(_ mode: ToggleMode) {
        var copy = settings
        copy.toggleMode = mode
        persist(copy)
        refresh()
    }

    func setPin(first: UUID?, second: UUID?) {
        var copy = settings
        copy.pinnedFirst = first
        copy.pinnedSecond = second
        persist(copy)
        refresh()
    }

    /// `nil` removes the shortcut.
    func setHotKey(_ hotKey: HotKey?) {
        var copy = settings
        copy.hotKey = hotKey
        persist(copy)
        syncHotKey()
        onChange?()
    }

    /// A registered hot key is swallowed by Carbon before any in-app event monitor sees it, so
    /// recording a replacement has to stand it down first.
    func suspendHotKey() {
        hotKeys.update(to: nil)
    }

    func resumeHotKey() {
        syncHotKey()
    }

    // MARK: - Internals

    /// Edits one record in place. Deliberately avoids `refresh()`: re-reading the HAL on every
    /// keystroke replaces `devices` wholesale and makes the rename field fight the user.
    private func updateRecord(id: UUID, _ mutate: (inout DeviceRecord) -> Void) {
        guard let index = settings.devices.firstIndex(where: { $0.id == id }) else { return }
        var copy = settings
        mutate(&copy.devices[index])
        guard copy != settings else { return }
        persist(copy)
        if let resolved = devices.firstIndex(where: { $0.id == id }) {
            devices[resolved].record = copy.devices[index]
        }
        onChange?()
    }

    private func persist(_ newSettings: Settings) {
        guard newSettings != settings else { return }
        settings = newSettings
        store.save(newSettings)
    }

    private func syncHotKey() {
        isHotKeyRejected = !hotKeys.update(to: settings.hotKey)
    }

    /// Any change counts as a use, including ones macOS makes for us (a headset connecting,
    /// Control Center, another app) — otherwise the toggle target goes stale.
    private func rememberCurrentDevice() {
        guard let current = currentDevice else { return }
        persist(settings.recordingUse(of: current.id))
    }

    private func handleSystemChange() {
        refresh()
        rememberCurrentDevice()
        onChange?()
    }
}
