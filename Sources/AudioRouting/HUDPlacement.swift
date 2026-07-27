import CoreGraphics
import Foundation

/// Where the "output changed" panel sits: horizontally centred, in the lower third — the same
/// place macOS puts its own volume and brightness HUDs.
///
/// Kept out of the view so the multi-screen arithmetic can be tested: screen frames are laid out
/// in one global space, so a monitor to the left of the main one has a negative origin.
public enum HUDPlacement {
    /// How far up from the bottom edge the panel starts, as a fraction of screen height.
    public static let bottomFraction: CGFloat = 0.18

    public static func frame(size: CGSize, in screen: CGRect) -> CGRect {
        let x = screen.midX - size.width / 2
        let y = screen.minY + screen.height * bottomFraction
        // Rounded to whole points so the text stays crisp, clamped so an over-wide panel
        // (a very long device name) can't slide off the screen.
        let clampedX = min(max(x, screen.minX), max(screen.minX, screen.maxX - size.width))
        let clampedY = min(max(y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGRect(origin: CGPoint(x: clampedX.rounded(), y: clampedY.rounded()), size: size)
    }
}
