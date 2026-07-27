import Foundation

/// The modifiers a shortcut can carry, kept independent of AppKit and Carbon so this stays
/// pure. The app layer translates them at the boundary.
public struct HotKeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)

    /// In the order macOS writes them.
    public var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

// Encoded as a bare number rather than `{"rawValue": n}`, which is what the synthesised
// conformance would produce for a struct.
extension HotKeyModifiers: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A system-wide keyboard shortcut, stored the way the hardware reports it.
///
/// Key codes are positional, which is what a global shortcut wants: the same physical key keeps
/// working when the keyboard layout changes. Names come from the table below so this file needs
/// no platform frameworks.
public struct HotKey: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: HotKeyModifiers

    public init(keyCode: UInt16, modifiers: HotKeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        modifiers.displayString + HotKey.keyName(for: keyCode)
    }

    /// A function key is safe on its own — that's the whole point of the extra keys on a
    /// programmable keyboard. Anything else would swallow a key you type with, so it needs at
    /// least one modifier.
    public var isUsable: Bool {
        !modifiers.isEmpty || HotKey.functionKeyCodes.contains(keyCode)
    }

    public static func keyName(for keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    public static let functionKeyCodes: Set<UInt16> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]

    /// Apple's virtual key codes (`Carbon/Events.h`), which never change.
    private static let keyNames: [UInt16: String] = [
        // Letters.
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G",
        0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N",
        0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U",
        0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z",
        // Digits and punctuation.
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x18: "=", 0x1B: "-", 0x21: "[", 0x1E: "]", 0x27: "'", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2F: ".", 0x32: "`",
        // Editing and navigation.
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x72: "Help", 0x73: "↖", 0x74: "⇞", 0x77: "↘", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        // Keypad.
        0x41: "Pad .", 0x43: "Pad *", 0x45: "Pad +", 0x47: "Pad Clear", 0x4B: "Pad /",
        0x4C: "Pad ↩", 0x4E: "Pad -", 0x51: "Pad =",
        0x52: "Pad 0", 0x53: "Pad 1", 0x54: "Pad 2", 0x55: "Pad 3", 0x56: "Pad 4",
        0x57: "Pad 5", 0x58: "Pad 6", 0x59: "Pad 7", 0x5B: "Pad 8", 0x5C: "Pad 9",
        // Function keys.
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18",
        0x50: "F19", 0x5A: "F20",
    ]
}
