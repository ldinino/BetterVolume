import AudioRouting
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            clickBehaviourSection
            Divider()
            shortcutSection
            Divider()
            devicesSection
            Divider()
            generalSection
        }
        .padding(16)
        .frame(width: 520, height: 640)
    }

    // MARK: - Keyboard shortcut

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard shortcut").font(.headline)
            Text("Does the same as a left click, from any app. A function key works on its own — handy for a programmable key.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HotKeyRecorder(hotKey: model.settings.hotKey,
                           onRecord: { model.setHotKey($0) },
                           onArmedChange: { $0 ? model.suspendHotKey() : model.resumeHotKey() })

            if model.isHotKeyRejected {
                Text("macOS refused that shortcut — another app is probably using it.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Start at login", isOn: $launchAtLogin)
                .disabled(!LaunchAtLogin.isAvailable)
                .onChange(of: launchAtLogin) { _, enabled in
                    if !LaunchAtLogin.setEnabled(enabled) {
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            if !LaunchAtLogin.isAvailable {
                Text("Available once BetterVolume is running from an app bundle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Left click behaviour

    private var clickBehaviourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Left click").font(.headline)

            Picker("", selection: toggleModeBinding) {
                Text("Flip between two devices").tag(ToggleMode.pinnedPair)
                Text("Return to the last used device").tag(ToggleMode.mostRecentlyUsed)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if model.settings.toggleMode == .pinnedPair {
                HStack(spacing: 8) {
                    devicePicker(selection: pinnedFirstBinding)
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                    devicePicker(selection: pinnedSecondBinding)
                }
                .padding(.leading, 20)

                if model.settings.pinnedPair.isEmpty {
                    Text("Pick two devices, or the last used device is used instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
    }

    private func devicePicker(selection: Binding<UUID?>) -> some View {
        Picker("", selection: selection) {
            Text("None").tag(UUID?.none)
            ForEach(model.settings.devices) { record in
                Text(record.displayName).tag(UUID?.some(record.id))
            }
        }
        .labelsHidden()
    }

    // MARK: - Devices

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices").font(.headline)
            Text("Rename anything you like, pick an icon, uncheck to keep it out of the menu, drag to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(model.devices) { device in
                    DeviceRow(model: model, device: device)
                }
                .onMove { model.moveDevices(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()

            Text("Disconnected devices stay in the list so their names and settings stick.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var toggleModeBinding: Binding<ToggleMode> {
        Binding(get: { model.settings.toggleMode },
                set: { model.setToggleMode($0) })
    }

    private var pinnedFirstBinding: Binding<UUID?> {
        Binding(get: { model.settings.pinnedFirst },
                set: { model.setPin(first: $0, second: model.settings.pinnedSecond) })
    }

    private var pinnedSecondBinding: Binding<UUID?> {
        Binding(get: { model.settings.pinnedSecond },
                set: { model.setPin(first: model.settings.pinnedFirst, second: $0) })
    }
}

private struct DeviceRow: View {
    let model: AppModel
    let device: ResolvedDevice

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: visibleBinding)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(device.record.isHidden ? "Hidden from the menu" : "Shown in the menu")

            iconMenu

            TextField(device.record.identity.name, text: aliasBinding)
                .textFieldStyle(.roundedBorder)

            Text(device.isCurrent ? "in use" : (device.isOnline ? "" : "offline"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var iconMenu: some View {
        Menu {
            Picker("Icon", selection: symbolBinding) {
                Label("Automatic", systemImage: DeviceIcons.automaticSymbolName(for: device))
                    .tag(String?.none)
                Divider()
                ForEach(DeviceIcons.catalog) { icon in
                    Label(icon.label, systemImage: icon.symbolName)
                        .tag(String?.some(icon.symbolName))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: DeviceIcons.symbolName(for: device))
                .foregroundStyle(device.isOnline ? .primary : .tertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .help("Choose an icon")
    }

    private var visibleBinding: Binding<Bool> {
        Binding(get: { !device.record.isHidden },
                set: { model.setHidden(!$0, for: device.id) })
    }

    private var aliasBinding: Binding<String> {
        Binding(get: { device.record.alias ?? "" },
                set: { model.setAlias($0, for: device.id) })
    }

    private var symbolBinding: Binding<String?> {
        Binding(get: { device.record.symbolName },
                set: { model.setSymbolName($0, for: device.id) })
    }
}
