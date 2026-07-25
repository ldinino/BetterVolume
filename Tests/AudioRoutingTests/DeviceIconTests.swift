import Foundation
import Testing

@testable import AudioRouting

@Suite("Device icons")
struct DeviceIconTests {
    private func resolved(_ device: AudioOutputDevice,
                          symbolName: String? = nil) -> ResolvedDevice {
        var record = DeviceRecord(identity: device.identity)
        record.symbolName = symbolName
        return ResolvedDevice(record: record, device: device, isCurrent: false)
    }

    @Test("A user's choice always beats the automatic guess")
    func overrideWins() {
        // The exact case that motivated this: 3.5 mm speakers macOS insists are headphones.
        let jack = makeDevice("External Headphones", objectID: 1, transport: .builtIn)
        #expect(DeviceIcons.automaticSymbolName(for: resolved(jack)) == "headphones")
        #expect(DeviceIcons.symbolName(for: resolved(jack, symbolName: "hifispeaker.2.fill"))
                    == "hifispeaker.2.fill")
    }

    @Test("Falls back to the guess once the override is cleared")
    func clearingRestoresAutomatic() {
        let hdmi = makeDevice("LG Monitor", objectID: 1, transport: .hdmi)
        #expect(DeviceIcons.symbolName(for: resolved(hdmi, symbolName: nil)) == "display")
    }

    @Test("Guesses from name, then transport")
    func automaticGuess() {
        let identity = DeviceIdentity(uid: "uid", modelUID: nil, name: "INZONE Buds")
        #expect(DeviceIcons.automaticSymbolName(identity: identity, transport: .bluetooth)
                    == "headphones")

        let plain = DeviceIdentity(uid: "uid", modelUID: nil, name: "Studio Display")
        #expect(DeviceIcons.automaticSymbolName(identity: plain, transport: .displayPort)
                    == "display")
        #expect(DeviceIcons.automaticSymbolName(identity: plain, transport: .airPlay)
                    == "airplayaudio")
        #expect(DeviceIcons.automaticSymbolName(identity: plain, transport: .usb)
                    == DeviceIcons.fallbackSymbolName)
        #expect(DeviceIcons.automaticSymbolName(identity: plain, transport: nil)
                    == DeviceIcons.fallbackSymbolName)
    }

    @Test("The catalog has no duplicates and offers a sane default")
    func catalogIsWellFormed() {
        let names = DeviceIcons.catalog.map(\.symbolName)
        #expect(Set(names).count == names.count)
        #expect(names.contains(DeviceIcons.fallbackSymbolName))
        #expect(DeviceIcons.catalog.allSatisfy { !$0.label.isEmpty })
    }

    @Test("An icon override survives a reconnect under a churned UID")
    func overrideSurvivesReconnect() {
        var record = makeRecord("INZONE Buds", uid: "uid:2110000", model: "model-buds")
        record.symbolName = "airpodspro"
        record.alias = "Desk Buds"
        let settings = Settings(devices: [record])

        let back = makeDevice("INZONE Buds", uid: "uid:4100000", model: "model-buds", objectID: 9)
        let result = DeviceRegistry.reconcile(settings: settings, live: [back], current: back)

        #expect(result.devices.count == 1)
        #expect(result.devices[0].record.symbolName == "airpodspro")
        #expect(result.devices[0].displayName == "Desk Buds")
        #expect(DeviceIcons.symbolName(for: result.devices[0]) == "airpodspro")
    }
}

@Suite("Display names")
struct DisplayNameTests {
    @Test("An alias replaces the hardware name")
    func aliasWins() {
        #expect(makeRecord("External Headphones", alias: "Desk Speakers").displayName
                    == "Desk Speakers")
    }

    @Test("Blank or whitespace-only aliases fall back to the hardware name")
    func blankFallsBack() {
        #expect(makeRecord("Mac Studio Speakers", alias: nil).displayName == "Mac Studio Speakers")
        #expect(makeRecord("Mac Studio Speakers", alias: "").displayName == "Mac Studio Speakers")
        #expect(makeRecord("Mac Studio Speakers", alias: "   ").displayName == "Mac Studio Speakers")
    }

    @Test("Stray whitespace from typing is trimmed for display but kept in the field")
    func trimsForDisplay() {
        let record = makeRecord("Mac Studio Speakers", alias: "  Desk  ")
        #expect(record.displayName == "Desk")
        #expect(record.alias == "  Desk  ")
    }
}
