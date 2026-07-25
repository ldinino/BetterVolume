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

    /// Called after any change so the AppKit status item can redraw.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let audio = HALAudioSystem()
    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.load()
        audio.onChange = { [weak self] in self?.handleSystemChange() }
        audio.startObserving()
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

    func setAlias(_ alias: String, for id: UUID) {
        guard let index = settings.devices.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        var copy = settings
        copy.devices[index].alias = trimmed.isEmpty ? nil : trimmed
        persist(copy)
        refresh()
    }

    func setHidden(_ isHidden: Bool, for id: UUID) {
        guard let index = settings.devices.firstIndex(where: { $0.id == id }) else { return }
        var copy = settings
        copy.devices[index].isHidden = isHidden
        persist(copy)
        refresh()
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

    // MARK: - Internals

    private func persist(_ newSettings: Settings) {
        guard newSettings != settings else { return }
        settings = newSettings
        store.save(newSettings)
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
