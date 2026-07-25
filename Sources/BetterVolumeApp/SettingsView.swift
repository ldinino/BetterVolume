import AudioRouting
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            clickBehaviourSection
            Divider()
            devicesSection
            Divider()
            generalSection
        }
        .padding(16)
        .frame(width: 480, height: 580)
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
            Text("Rename anything you like, uncheck to keep it out of the menu, drag to reorder.")
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

    @State private var alias: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: visibleBinding)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(device.record.isHidden ? "Hidden from the menu" : "Shown in the menu")

            Image(systemName: DeviceSymbol.name(for: device))
                .frame(width: 18)
                .foregroundStyle(device.isOnline ? .primary : .tertiary)

            TextField(device.record.identity.name, text: $alias)
                .textFieldStyle(.roundedBorder)
                .focused($isEditing)
                .onSubmit { commit() }
                .onChange(of: isEditing) { _, editing in
                    if !editing { commit() }
                }

            Text(device.isCurrent ? "in use" : (device.isOnline ? "" : "offline"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .task(id: device.record.alias) { alias = device.record.alias ?? "" }
    }

    private var visibleBinding: Binding<Bool> {
        Binding(get: { !device.record.isHidden },
                set: { model.setHidden(!$0, for: device.id) })
    }

    private func commit() {
        guard alias != (device.record.alias ?? "") else { return }
        model.setAlias(alias, for: device.id)
    }
}
