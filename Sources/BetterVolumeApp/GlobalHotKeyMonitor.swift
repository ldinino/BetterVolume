import AudioRouting
import Carbon.HIToolbox

/// Ours, so the shared Carbon handler can ignore other people's hot keys.
private let hotKeySignature = OSType(0x4256_4B59)  // 'BVKY'

/// Registers a system-wide key with Carbon's `RegisterEventHotKey`.
///
/// Carbon is deliberate: it is the only API that delivers a global key press without asking the
/// user for Accessibility / Input Monitoring permission, which `NSEvent` global monitors and
/// event taps both require. The handler is dispatched on the main thread.
@MainActor
final class GlobalHotKeyMonitor {
    /// Called on every press of the registered key.
    var action: (@MainActor () -> Void)?

    private var current: HotKey?
    private var isRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static var active: GlobalHotKeyMonitor?

    /// Registers `hotKey`, replacing whatever was registered before. `nil` just unregisters.
    ///
    /// Returns `false` when the system refused the key — nearly always because another app
    /// already owns that combination.
    @discardableResult
    func update(to hotKey: HotKey?) -> Bool {
        guard hotKey != current || (hotKey != nil && !isRegistered) else { return true }
        unregister()
        current = hotKey
        guard let hotKey else { return true }
        guard hotKey.isUsable else { return false }

        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: hotKeySignature, id: 1)
        let status = RegisterEventHotKey(UInt32(hotKey.keyCode),
                                         UInt32(carbonModifiers(hotKey.modifiers)),
                                         id,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        isRegistered = true
        return true
    }

    // MARK: - Internals

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        isRegistered = false
    }

    private func installHandler() {
        Self.active = self
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &id)
            guard status == noErr, id.signature == hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches hot keys on the main thread, which is where everything this
            // touches lives.
            MainActor.assumeIsolated { GlobalHotKeyMonitor.active?.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func carbonModifiers(_ modifiers: HotKeyModifiers) -> Int {
        var value = 0
        if modifiers.contains(.control) { value |= controlKey }
        if modifiers.contains(.option) { value |= optionKey }
        if modifiers.contains(.shift) { value |= shiftKey }
        if modifiers.contains(.command) { value |= cmdKey }
        return value
    }
}
