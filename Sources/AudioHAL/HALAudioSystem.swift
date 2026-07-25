import AudioRouting
import CoreAudio
import Foundation

public struct AudioSystemError: LocalizedError {
    public let operation: String
    public let status: OSStatus

    public var errorDescription: String? {
        "\(operation) failed (OSStatus \(status))"
    }
}

public struct VolumeControl: Equatable, Sendable {
    public var value: Float
    public var isMuted: Bool
    public var canMute: Bool
}

/// The only type that talks to the Core Audio HAL.
///
/// Everything here is main-actor isolated; HAL notifications arrive on a private queue and are
/// hopped back to the main actor before they touch any state.
@MainActor
public final class HALAudioSystem {
    /// Called whenever the device list or the default output changes, including changes made by
    /// macOS itself (unplugging a headset, Control Center, another app).
    public var onChange: (@MainActor () -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let notificationQueue = DispatchQueue(label: "com.bettervolume.hal-notifications")
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init() {}

    deinit {
        // Listeners are torn down explicitly via stopObserving(); nothing to do here.
    }

    // MARK: - Reading

    public func outputDevices() -> [AudioOutputDevice] {
        allDeviceIDs().compactMap(makeOutputDevice)
    }

    public func defaultOutput() -> AudioOutputDevice? {
        guard let id = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        return makeOutputDevice(id)
    }

    // MARK: - Writing

    /// Makes `device` the default output. The device is re-resolved by UID first, because a
    /// cached `AudioObjectID` goes stale as soon as the device list changes.
    public func setDefaultOutput(_ device: AudioOutputDevice) throws {
        let live = outputDevices()
        guard let target = live.first(where: { $0.identity.uid == device.identity.uid })
                ?? live.first(where: { $0.objectID == device.objectID }) else {
            throw AudioSystemError(operation: "resolve \(device.identity.name)",
                                   status: kAudioHardwareBadDeviceError)
        }

        try setDefaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice, target.objectID)

        // Keep alert sounds with the music, the way Apple's own Sound menu does. Not every
        // device is allowed to be the system output, so this half is best-effort.
        if canBeDefaultSystemDevice(target.objectID) {
            try? setDefaultDeviceID(kAudioHardwarePropertyDefaultSystemOutputDevice, target.objectID)
        }
    }

    // MARK: - Volume

    /// Reads the device's volume, or `nil` when the device has no volume control.
    ///
    /// USB and HDMI outputs commonly report nothing here — macOS has no software volume for them
    /// either, so callers should disable the control rather than fake one.
    public func volumeControl(for device: AudioOutputDevice) -> VolumeControl? {
        guard let id = resolve(device) else { return nil }
        let elements = volumeElements(id)
        guard !elements.isEmpty else { return nil }

        let values = elements.compactMap { scalar(id, Self.volumeAddress($0)) }
        guard !values.isEmpty else { return nil }

        let muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return VolumeControl(value: values.reduce(0, +) / Float(values.count),
                             isMuted: integer(id, muteAddress) == 1,
                             canMute: isSettable(id, muteAddress))
    }

    public func setVolume(_ value: Float, for device: AudioOutputDevice) {
        guard let id = resolve(device) else { return }
        let clamped = min(max(value, 0), 1)
        for element in volumeElements(id) {
            var address = Self.volumeAddress(element)
            var scalar = clamped
            AudioObjectSetPropertyData(id, &address, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &scalar)
        }
        // Unmute on any deliberate volume change, the way the system slider behaves.
        if clamped > 0 { setMuted(false, for: device) }
    }

    public func setMuted(_ muted: Bool, for device: AudioOutputDevice) {
        guard let id = resolve(device) else { return }
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard isSettable(id, address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// The main element if it carries volume, otherwise the individual channels.
    private func volumeElements(_ id: AudioObjectID) -> [AudioObjectPropertyElement] {
        if isSettable(id, Self.volumeAddress(kAudioObjectPropertyElementMain)) {
            return [kAudioObjectPropertyElementMain]
        }
        return (1...UInt32(max(outputChannelCount(id), 1)))
            .filter { isSettable(id, Self.volumeAddress($0)) }
    }

    private static func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        address(kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element)
    }

    /// Cheap in the common case: a cached `AudioObjectID` is trusted only while it still reports
    /// the UID we expect, which matters because volume drags call this on every event.
    private func resolve(_ device: AudioOutputDevice) -> AudioObjectID? {
        let uid = string(device.objectID, Self.address(kAudioDevicePropertyDeviceUID))
        if uid == device.identity.uid { return device.objectID }
        return outputDevices().first { $0.identity.uid == device.identity.uid }?.objectID
    }

    private func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private func scalar(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var size = UInt32(MemoryLayout<Float32>.size)
        var value: Float32 = 0
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    // MARK: - Observing

    public func startObserving() {
        guard listeners.isEmpty else { return }
        observe(kAudioHardwarePropertyDevices)
        observe(kAudioHardwarePropertyDefaultOutputDevice)
    }
    public func stopObserving() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, notificationQueue, block)
        }
        listeners.removeAll()
    }

    private func observe(_ selector: AudioObjectPropertySelector) {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
        let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, notificationQueue, block)
        if status == noErr {
            listeners.append((address, block))
        }
    }

    // MARK: - Device construction

    private func makeOutputDevice(_ id: AudioObjectID) -> AudioOutputDevice? {
        guard outputChannelCount(id) > 0 else { return nil }
        guard let uid = string(id, Self.address(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = string(id, Self.address(kAudioObjectPropertyName)) ?? uid

        return AudioOutputDevice(
            objectID: id,
            identity: DeviceIdentity(uid: uid,
                                     modelUID: string(id, Self.address(kAudioDevicePropertyModelUID)),
                                     name: name),
            transport: transportType(id),
            supportsVolume: hasSettableVolume(id)
        )
    }

    private func transportType(_ id: AudioObjectID) -> TransportType {
        switch integer(id, Self.address(kAudioDevicePropertyTransportType)) {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeAggregate: .aggregate
        default: .other
        }
    }

    /// Note: USB and HDMI outputs typically report no volume control at all — macOS has none for
    /// them either, so callers should disable rather than fake a slider.
    private func hasSettableVolume(_ id: AudioObjectID) -> Bool {
        isSettable(id, Self.volumeAddress(kAudioObjectPropertyElementMain))
            || !volumeElements(id).isEmpty
    }

    private func canBeDefaultSystemDevice(_ id: AudioObjectID) -> Bool {
        let address = Self.address(kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
                                   scope: kAudioObjectPropertyScopeOutput)
        return integer(id, address) == 1
    }

    // MARK: - HAL plumbing

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func allDeviceIDs() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var value: AudioObjectID = 0
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &value) == noErr,
              value != kAudioObjectUnknown else { return nil }
        return value
    }

    private func setDefaultDeviceID(_ selector: AudioObjectPropertySelector, _ id: AudioObjectID) throws {
        var address = Self.address(selector)
        var value = id
        let status = AudioObjectSetPropertyData(systemObject, &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &value)
        guard status == noErr else {
            throw AudioSystemError(operation: "set default device", status: status)
        }
    }

    private func outputChannelCount(_ id: AudioObjectID) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration,
                                   scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func string(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    private func integer(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
