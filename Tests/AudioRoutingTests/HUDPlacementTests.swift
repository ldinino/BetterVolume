import Foundation
import Testing

@testable import AudioRouting

@Suite("HUD placement")
struct HUDPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("Centred horizontally and in the lower third")
    func centred() {
        let frame = HUDPlacement.frame(size: CGSize(width: 300, height: 120), in: screen)
        #expect(frame.midX == screen.midX)
        #expect(frame.minY == (1080 * HUDPlacement.bottomFraction).rounded())
        #expect(frame.minY > screen.minY)
        #expect(frame.maxY < screen.midY)
    }

    @Test("Follows the screen it is shown on, including one left of the main display")
    func secondScreen() {
        // Screen frames share one coordinate space, so a display to the left is at negative x.
        let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let frame = HUDPlacement.frame(size: CGSize(width: 300, height: 120), in: left)
        #expect(frame.midX == left.midX)
        #expect(left.contains(frame))
    }

    @Test("A panel wider than the screen still starts on it")
    func clamps() {
        let frame = HUDPlacement.frame(size: CGSize(width: 3000, height: 120), in: screen)
        #expect(frame.minX == screen.minX)
        #expect(frame.minY >= screen.minY)
    }
}
