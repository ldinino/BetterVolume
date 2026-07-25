import Foundation
import Testing

@testable import AudioRouting

@Suite("ToggleResolver")
struct ToggleResolverTests {
    /// Builds a reconciled world: every name given is a known device, `offline` names have no
    /// live device behind them, and `current` is the active output.
    func world(_ names: [String],
               current: String?,
               offline: Set<String> = [],
               hidden: Set<String> = []) -> (Settings, [ResolvedDevice]) {
        let records = names.map { makeRecord($0, hidden: hidden.contains($0)) }
        var live: [AudioOutputDevice] = []
        var objectID: UInt32 = 1
        for record in records where !offline.contains(record.identity.name) {
            live.append(makeDevice(record.identity.name, uid: record.identity.uid, objectID: objectID))
            objectID += 1
        }
        let currentDevice = live.first { $0.identity.name == current }
        let result = DeviceRegistry.reconcile(settings: Settings(devices: records),
                                              live: live,
                                              current: currentDevice)
        return (result.settings, result.devices)
    }

    func id(_ devices: [ResolvedDevice], _ name: String) -> UUID {
        devices.first { $0.record.identity.name == name }!.id
    }

    /// Same devices, different active output — without minting new record IDs.
    func switching(_ devices: [ResolvedDevice], to name: String) -> [ResolvedDevice] {
        devices.map {
            ResolvedDevice(record: $0.record,
                           device: $0.device,
                           isCurrent: $0.record.identity.name == name)
        }
    }

    @Test("Pinned pair flips in both directions")
    func pinnedPairFlips() {
        var (settings, devices) = world(["INZONE Buds", "External Headphones", "DELL U2722D"],
                                        current: "INZONE Buds")
        settings.pinnedFirst = id(devices, "INZONE Buds")
        settings.pinnedSecond = id(devices, "External Headphones")

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "External Headphones")

        let flipped = switching(devices, to: "External Headphones")
        #expect(ToggleResolver.target(settings: settings, devices: flipped)?.displayName == "INZONE Buds")
    }

    @Test("A device outside the pair jumps into the pair")
    func jumpsIntoPair() {
        var (settings, devices) = world(["INZONE Buds", "External Headphones", "DELL U2722D"],
                                        current: "DELL U2722D")
        settings.pinnedFirst = id(devices, "INZONE Buds")
        settings.pinnedSecond = id(devices, "External Headphones")

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "INZONE Buds")
    }

    @Test("An offline pin falls back instead of dead-ending")
    func offlinePinFallsBack() {
        var (settings, devices) = world(["INZONE Buds", "External Headphones", "DELL U2722D"],
                                        current: "External Headphones",
                                        offline: ["INZONE Buds"])
        settings.pinnedFirst = id(devices, "INZONE Buds")
        settings.pinnedSecond = id(devices, "External Headphones")

        let target = ToggleResolver.target(settings: settings, devices: devices)
        #expect(target?.displayName == "DELL U2722D")
        #expect(target?.isOnline == true)
    }

    @Test("A pinned device is reachable even when hidden from the menu")
    func pinnedBeatsHidden() {
        var (settings, devices) = world(["INZONE Buds", "DELL U2722D"],
                                        current: "INZONE Buds",
                                        hidden: ["DELL U2722D"])
        settings.pinnedFirst = id(devices, "INZONE Buds")
        settings.pinnedSecond = id(devices, "DELL U2722D")

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "DELL U2722D")
    }

    @Test("A half-configured pair falls back to most-recently-used")
    func halfPairFallsBack() {
        var (settings, devices) = world(["INZONE Buds", "External Headphones", "DELL U2722D"],
                                        current: "INZONE Buds")
        settings.pinnedFirst = id(devices, "DELL U2722D")
        settings = settings.recordingUse(of: id(devices, "External Headphones"))

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "External Headphones")
    }

    @Test("Most-recently-used mode returns the last other device")
    func mruMode() {
        var (settings, devices) = world(["INZONE Buds", "External Headphones", "DELL U2722D"],
                                        current: "DELL U2722D")
        settings.toggleMode = .mostRecentlyUsed
        settings = settings
            .recordingUse(of: id(devices, "External Headphones"))
            .recordingUse(of: id(devices, "DELL U2722D"))

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "External Headphones")
    }

    @Test("Hidden devices are skipped when there is no pin")
    func hiddenSkipped() {
        let (settings, devices) = world(["INZONE Buds", "DELL U2722D", "External Headphones"],
                                        current: "INZONE Buds",
                                        hidden: ["DELL U2722D"])

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "External Headphones")
    }

    @Test("A single connected device has nowhere to go")
    func singleDevice() {
        let (settings, devices) = world(["INZONE Buds", "External Headphones"],
                                        current: "INZONE Buds",
                                        offline: ["External Headphones"])

        #expect(ToggleResolver.target(settings: settings, devices: devices) == nil)
    }

    @Test("With no pin and no history it cycles in menu order")
    func cyclesInOrder() {
        let (settings, devices) = world(["INZONE Buds", "External Headphones", "DELL U2722D"],
                                        current: "External Headphones")

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "DELL U2722D")
    }

    @Test("An unknown current device still produces a target")
    func unknownCurrent() {
        let (settings, devices) = world(["INZONE Buds", "External Headphones"], current: nil)

        #expect(ToggleResolver.target(settings: settings, devices: devices)?.displayName == "INZONE Buds")
    }
}
