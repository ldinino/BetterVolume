import AppKit
import AudioRouting
import SwiftUI

extension HotKey {
    /// `nil` when the press isn't usable as a shortcut — a bare letter, or a modifier on its own.
    ///
    /// `.function` and `.numericPad` are deliberately ignored: macOS sets them for F-keys and
    /// arrows, so treating them as modifiers would make F19 record as "fn F19".
    init?(event: NSEvent) {
        var modifiers: HotKeyModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }

        let candidate = HotKey(keyCode: event.keyCode, modifiers: modifiers)
        guard candidate.isUsable else { return nil }
        self = candidate
    }
}

/// Records the next key press while armed, using a local event monitor — the settings window is
/// key at that point, so no permission or custom first responder is needed.
struct HotKeyRecorder: View {
    let hotKey: HotKey?
    let onRecord: (HotKey?) -> Void
    let onArmedChange: (Bool) -> Void

    @State private var isArmed = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { isArmed ? disarm() : arm() }) {
                Text(label)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 170)

            if hotKey != nil, !isArmed {
                Button("Clear") { onRecord(nil) }
            }

            if isArmed {
                Text(rejected ? "That key needs ⌘, ⌥, ⌃ or ⇧." : "⎋ to cancel.")
                    .font(.caption)
                    .foregroundStyle(rejected ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
        .onDisappear(perform: disarm)
    }

    private var label: String {
        if isArmed { return "Press a key…" }
        return hotKey?.displayString ?? "Record shortcut"
    }

    private func arm() {
        guard monitor == nil else { return }
        isArmed = true
        rejected = false
        onArmedChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil  // Swallow it, or the key also reaches the window.
        }
    }

    private func disarm() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isArmed else { return }
        isArmed = false
        rejected = false
        onArmedChange(false)
    }

    private func handle(_ event: NSEvent) {
        let modified = !event.modifierFlags
            .intersection([.command, .option, .control, .shift]).isEmpty
        if event.keyCode == 0x35, !modified {  // Bare escape cancels; ⌘⎋ is still recordable.
            disarm()
            return
        }
        guard let recorded = HotKey(event: event) else {
            rejected = true
            return
        }
        disarm()
        onRecord(recorded)
    }
}
