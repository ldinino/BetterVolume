import AppKit
import AudioRouting

enum AppInfo {
    static let name = "BetterVolume"
    /// Also used as the app bundle identifier — change the prefix to your team's before signing.
    static let bundleIdentifier = "com.bettervolume.BetterVolume"
}

enum DeviceSymbol {
    private static let headphoneHints = ["headphone", "buds", "airpods", "headset", "earphone", "earbud"]

    static func name(for device: ResolvedDevice) -> String {
        let haystack = "\(device.record.identity.name) \(device.record.identity.uid)".lowercased()
        if headphoneHints.contains(where: haystack.contains) { return "headphones" }

        return switch device.device?.transport {
        case .hdmi, .displayPort: "display"
        case .airPlay: "airplayaudio"
        default: "hifispeaker.fill"
        }
    }

    static func image(named symbol: String, description: String, pointSize: CGFloat = 14) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        image?.isTemplate = true
        return image
    }
}
