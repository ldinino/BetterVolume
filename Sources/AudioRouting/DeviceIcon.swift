import Foundation

/// One pickable icon: an SF Symbol plus the name shown in the menu.
public struct DeviceIcon: Hashable, Sendable, Identifiable {
    public var symbolName: String
    public var label: String

    public var id: String { symbolName }

    public init(symbolName: String, label: String) {
        self.symbolName = symbolName
        self.label = label
    }
}

/// Icon selection, kept out of the UI so it stays testable.
///
/// macOS reports anything on the 3.5 mm jack as headphones, so the automatic guess is only ever
/// a starting point — `DeviceRecord.symbolName` overrides it and is what the user actually sees.
public enum DeviceIcons {
    /// Used whenever nothing better is known, and as the fallback for a symbol the running
    /// version of macOS doesn't ship.
    public static let fallbackSymbolName = "hifispeaker.fill"

    /// The choices offered in Settings. All exist in SF Symbols 5 (macOS 14, our minimum).
    public static let catalog: [DeviceIcon] = [
        DeviceIcon(symbolName: "hifispeaker.fill", label: "Speaker"),
        DeviceIcon(symbolName: "hifispeaker.2.fill", label: "Speaker Pair"),
        DeviceIcon(symbolName: "speaker.wave.2.fill", label: "Volume"),
        DeviceIcon(symbolName: "homepod.fill", label: "HomePod"),
        DeviceIcon(symbolName: "homepodmini.fill", label: "HomePod mini"),
        DeviceIcon(symbolName: "headphones", label: "Headphones"),
        DeviceIcon(symbolName: "airpods", label: "AirPods"),
        DeviceIcon(symbolName: "airpodspro", label: "AirPods Pro"),
        DeviceIcon(symbolName: "airpodsmax", label: "AirPods Max"),
        DeviceIcon(symbolName: "earbuds", label: "Earbuds"),
        DeviceIcon(symbolName: "display", label: "Display"),
        DeviceIcon(symbolName: "tv", label: "TV"),
        DeviceIcon(symbolName: "desktopcomputer", label: "Desktop Mac"),
        DeviceIcon(symbolName: "laptopcomputer", label: "Laptop"),
        DeviceIcon(symbolName: "airplayaudio", label: "AirPlay"),
        DeviceIcon(symbolName: "cable.connector", label: "Cable"),
        DeviceIcon(symbolName: "dot.radiowaves.left.and.right", label: "Wireless"),
        DeviceIcon(symbolName: "waveform", label: "Waveform"),
        DeviceIcon(symbolName: "music.note", label: "Music"),
        DeviceIcon(symbolName: "pianokeys", label: "Piano"),
        DeviceIcon(symbolName: "guitars.fill", label: "Guitars"),
        DeviceIcon(symbolName: "radio.fill", label: "Radio"),
        DeviceIcon(symbolName: "gamecontroller.fill", label: "Game Controller"),
        DeviceIcon(symbolName: "car.fill", label: "Car"),
        DeviceIcon(symbolName: "iphone", label: "iPhone"),
        DeviceIcon(symbolName: "ipad", label: "iPad"),
    ]

    private static let headphoneHints = [
        "headphone", "buds", "airpods", "headset", "earphone", "earbud",
    ]

    /// The symbol to draw: the user's choice if there is one, otherwise the guess.
    public static func symbolName(for device: ResolvedDevice) -> String {
        device.record.symbolName ?? automaticSymbolName(for: device)
    }

    /// What we'd pick if the user hadn't chosen anything.
    public static func automaticSymbolName(for device: ResolvedDevice) -> String {
        automaticSymbolName(identity: device.record.identity, transport: device.device?.transport)
    }

    public static func automaticSymbolName(identity: DeviceIdentity,
                                           transport: TransportType?) -> String {
        let haystack = "\(identity.name) \(identity.uid)".lowercased()
        if headphoneHints.contains(where: haystack.contains) { return "headphones" }

        return switch transport {
        case .hdmi, .displayPort: "display"
        case .airPlay: "airplayaudio"
        default: fallbackSymbolName
        }
    }
}
