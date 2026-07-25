import Foundation

/// A live output device as reported by the audio system.
///
/// `objectID` is transient — it is only valid until the device list changes, so it is never
/// persisted and never used to match against saved settings.
public struct AudioOutputDevice: Hashable, Sendable, Identifiable {
    public var objectID: UInt32
    public var identity: DeviceIdentity
    public var transport: TransportType
    public var supportsVolume: Bool

    public var id: UInt32 { objectID }

    public init(objectID: UInt32,
                identity: DeviceIdentity,
                transport: TransportType,
                supportsVolume: Bool) {
        self.objectID = objectID
        self.identity = identity
        self.transport = transport
        self.supportsVolume = supportsVolume
    }
}

public enum TransportType: String, Codable, Sendable {
    case builtIn
    case usb
    case bluetooth
    case hdmi
    case displayPort
    case airPlay
    case thunderbolt
    case virtual
    case aggregate
    case other
}
