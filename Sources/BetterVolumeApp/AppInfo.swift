import AppKit
import AudioRouting

enum AppInfo {
    static let name = "BetterVolume"
    /// Also used as the app bundle identifier — change the prefix to your team's before signing.
    static let bundleIdentifier = "com.bettervolume.BetterVolume"

    /// Credits for the standard About panel. The app icon is LGPL, so its attribution has to
    /// travel with the binary and not just live in the repo's THIRD-PARTY-NOTICES.md.
    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        var linked = attributes
        if let url = URL(string: "https://invent.kde.org/frameworks/oxygen-icons") {
            linked[.link] = url
        }

        let credits = NSMutableAttributedString(string: "App icon from the ", attributes: attributes)
        credits.append(NSAttributedString(string: "Oxygen icon theme", attributes: linked))
        credits.append(NSAttributedString(string: " by the Oxygen Team, used under the LGPL v3.",
                                          attributes: attributes))
        return credits
    }
}

enum DeviceSymbol {
    /// Point size of the menu bar glyph.
    static let statusPointSize: CGFloat = 14

    static func name(for device: ResolvedDevice) -> String {
        DeviceIcons.symbolName(for: device)
    }

    static func image(named symbol: String, description: String, pointSize: CGFloat = 14) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: DeviceIcons.fallbackSymbolName,
                       accessibilityDescription: description)
        let configured = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        configured?.isTemplate = true
        return configured
    }

    /// The menu bar glyph, centred on a canvas that is the same for every icon.
    ///
    /// SF Symbols vary a lot in size — 8pt wide for `cable.connector`, 23pt for `airpodspro` —
    /// and the status item is `variableLength`, so without a common canvas the item resizes and
    /// the icon jumps sideways every time the output changes.
    static func statusItemImage(named symbol: String, description: String) -> NSImage? {
        guard let glyph = image(named: symbol, description: description, pointSize: statusPointSize)
        else { return nil }

        let canvas = statusItemCanvas
        let fit = min(1, min(canvas.width / glyph.size.width, canvas.height / glyph.size.height))
        let size = NSSize(width: (glyph.size.width * fit).rounded(.down),
                          height: (glyph.size.height * fit).rounded(.down))

        let padded = NSImage(size: canvas, flipped: false) { _ in
            // Integral origins: a half-pixel offset is exactly the wobble we're removing.
            let origin = NSPoint(x: ((canvas.width - size.width) / 2).rounded(),
                                 y: ((canvas.height - size.height) / 2).rounded())
            glyph.draw(in: NSRect(origin: origin, size: size))
            return true
        }
        padded.isTemplate = true
        padded.accessibilityDescription = description
        return padded
    }

    /// Sized so the common icons draw at their natural size; the few oversized ones
    /// (`airpodspro`, `gamecontroller.fill`) are scaled down to fit rather than dragging the
    /// whole status item wider for everyone.
    private static let statusItemCanvas = NSSize(width: 20, height: 18)
}
