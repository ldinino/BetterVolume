import Foundation
import Testing

@testable import AudioRouting

@Suite("Hot keys")
struct HotKeyTests {
    @Test("A function key stands alone; anything else needs a modifier")
    func usability() {
        // The motivating case: a programmable keyboard sending a bare F19.
        #expect(HotKey(keyCode: 0x50).isUsable)
        #expect(HotKey(keyCode: 0x7A).isUsable)
        #expect(!HotKey(keyCode: 0x01).isUsable)
        #expect(HotKey(keyCode: 0x01, modifiers: [.command, .option]).isUsable)
    }

    @Test("Reads the way macOS writes shortcuts")
    func display() {
        #expect(HotKey(keyCode: 0x50).displayString == "F19")
        #expect(HotKey(keyCode: 0x01, modifiers: [.command, .shift, .option, .control])
                    .displayString == "⌃⌥⇧⌘S")
        #expect(HotKey(keyCode: 0x31, modifiers: [.option]).displayString == "⌥Space")
        #expect(HotKey(keyCode: 0xFF, modifiers: [.command]).displayString == "⌘Key 255")
    }

    @Test("The key table has no duplicate names and covers every function key")
    func keyTableIsWellFormed() {
        let names = HotKey.functionKeyCodes.map { HotKey.keyName(for: $0) }
        #expect(Set(names).count == HotKey.functionKeyCodes.count)
        #expect(!names.contains { $0.hasPrefix("Key ") })
        #expect(HotKey.functionKeyCodes.count == 20)
    }

    @Test("Round-trips through settings, modifiers included")
    func codableRoundTrip() throws {
        let hotKey = HotKey(keyCode: 0x50, modifiers: [.control, .command])
        let settings = Settings(hotKey: hotKey)
        let decoded = try JSONDecoder().decode(Settings.self,
                                               from: JSONEncoder().encode(settings))
        #expect(decoded.hotKey == hotKey)

        // Modifiers encode as a bare number, not a wrapper object.
        let raw = try JSONEncoder().encode(HotKeyModifiers([.control, .command]))
        #expect(String(decoding: raw, as: UTF8.self) == "9")
    }

    @Test("Settings saved before the shortcut existed still decode")
    func decodesOlderSettings() throws {
        let json = Data(#"{"devices":[],"toggleMode":"pinnedPair","recents":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.hotKey == nil)
    }
}
