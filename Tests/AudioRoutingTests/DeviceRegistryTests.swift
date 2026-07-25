import Foundation
import Testing

@testable import AudioRouting

// MARK: - Helpers

func makeDevice(_ name: String,
                uid: String? = nil,
                model: String? = nil,
                objectID: UInt32,
                transport: TransportType = .usb) -> AudioOutputDevice {
    AudioOutputDevice(
        objectID: objectID,
        identity: DeviceIdentity(uid: uid ?? "uid-\(name)", modelUID: model, name: name),
        transport: transport,
        supportsVolume: false
    )
}

func makeRecord(_ name: String,
                uid: String? = nil,
                model: String? = nil,
                alias: String? = nil,
                hidden: Bool = false) -> DeviceRecord {
    DeviceRecord(
        identity: DeviceIdentity(uid: uid ?? "uid-\(name)", modelUID: model, name: name),
        alias: alias,
        isHidden: hidden
    )
}

// MARK: - Registry

@Suite("DeviceRegistry")
struct DeviceRegistryTests {
    @Test("First run creates a record for every live device")
    func firstRun() {
        let buds = makeDevice("INZONE Buds", objectID: 1)
        let speakers = makeDevice("Mac Studio Speakers", objectID: 2, transport: .builtIn)

        let result = DeviceRegistry.reconcile(settings: Settings(), live: [buds, speakers], current: buds)

        #expect(result.devices.count == 2)
        #expect(result.devices.map(\.isOnline) == [true, true])
        #expect(result.current?.displayName == "INZONE Buds")
        #expect(result.menuDevices.count == 2)
    }

    @Test("A changed UID does not lose the alias or hidden flag")
    func uidChurnKeepsSettings() {
        // Exactly the churn observed on this Mac: the USB location token changes.
        let saved = makeRecord("INZONE Buds",
                               uid: "AppleUSBAudioEngine:Sony:INZONE Buds:2110000:2,1",
                               model: "INZONE Buds:054C:0EC3",
                               alias: "Buds")
        let reconnected = makeDevice("INZONE Buds",
                                     uid: "AppleUSBAudioEngine:Sony:INZONE Buds:4100000:2,1",
                                     model: "INZONE Buds:054C:0EC3",
                                     objectID: 7)

        let result = DeviceRegistry.reconcile(settings: Settings(devices: [saved]),
                                              live: [reconnected],
                                              current: reconnected)

        #expect(result.devices.count == 1, "should match the existing record, not create a second one")
        #expect(result.devices[0].record.id == saved.id)
        #expect(result.devices[0].displayName == "Buds")
        #expect(result.devices[0].record.identity.uid == reconnected.identity.uid, "identity should be refreshed")
    }

    @Test("Disconnected devices are retained as offline records")
    func disconnectedDevicesRetained() {
        let settings = Settings(devices: [makeRecord("INZONE Buds"), makeRecord("External Headphones")])
        let headphones = makeDevice("External Headphones", objectID: 3, transport: .builtIn)

        let result = DeviceRegistry.reconcile(settings: settings, live: [headphones], current: headphones)

        #expect(result.devices.count == 2)
        #expect(result.devices[0].isOnline == false)
        #expect(result.devices[1].isOnline)
        #expect(result.menuDevices.count == 1)
    }

    @Test("A UID match wins over a name match for the same device")
    func strongestMatchWins() {
        let nameOnly = makeRecord("Speakers", uid: "old-uid")
        let uidMatch = makeRecord("Something Else", uid: "real-uid")
        let live = makeDevice("Speakers", uid: "real-uid", objectID: 9)

        let result = DeviceRegistry.reconcile(settings: Settings(devices: [nameOnly, uidMatch]),
                                              live: [live],
                                              current: nil)

        #expect(result.devices[0].isOnline == false)
        #expect(result.devices[1].isOnline)
        #expect(result.devices[1].record.identity.name == "Speakers", "identity refreshed from live device")
    }

    @Test("Hidden devices stay out of the menu but keep their record")
    func hiddenExcludedFromMenu() {
        let settings = Settings(devices: [makeRecord("DELL U2722D", hidden: true), makeRecord("INZONE Buds")])
        let dell = makeDevice("DELL U2722D", objectID: 1, transport: .hdmi)
        let buds = makeDevice("INZONE Buds", objectID: 2)

        let result = DeviceRegistry.reconcile(settings: settings, live: [dell, buds], current: buds)

        #expect(result.devices.count == 2)
        #expect(result.menuDevices.map(\.displayName) == ["INZONE Buds"])
    }

    @Test("A pin pointing at an unknown device is dropped")
    func unknownPinPruned() {
        let record = makeRecord("INZONE Buds")
        let settings = Settings(devices: [record], pinnedFirst: record.id, pinnedSecond: UUID())
        let live = makeDevice("INZONE Buds", objectID: 1)

        let result = DeviceRegistry.reconcile(settings: settings, live: [live], current: live)

        #expect(result.settings.pinnedFirst == record.id)
        #expect(result.settings.pinnedSecond == nil)
        #expect(result.settings.pinnedPair.isEmpty, "a half pair is not usable")
    }
}

// MARK: - Settings

@Suite("Settings")
struct SettingsTests {
    @Test("Recording a use moves the device to the front without duplicating it")
    func recentsOrdering() {
        let a = UUID(), b = UUID()
        let settings = Settings(recents: [a, b]).recordingUse(of: b)
        #expect(settings.recents == [b, a])
    }

    @Test("Recents are capped")
    func recentsCapped() {
        var settings = Settings()
        for _ in 0..<(Settings.recentsLimit + 5) {
            settings = settings.recordingUse(of: UUID())
        }
        #expect(settings.recents.count == Settings.recentsLimit)
    }
}
