import Foundation

/// How a device identifies itself to Core Audio.
///
/// `uid` is the obvious key but it is **not** stable: a USB device's UID embeds a
/// location/session token that changes across reconnects (verified on this machine — the same
/// headset appears in macOS's own settings as both `…INZONE Buds:2110000:2,1` and
/// `…:4100000:2,1`). `modelUID` encodes vendor/product and survives reconnects, so it is the
/// stronger key when the UID has churned.
public struct DeviceIdentity: Codable, Hashable, Sendable {
    public var uid: String
    public var modelUID: String?
    public var name: String

    public init(uid: String, modelUID: String? = nil, name: String) {
        self.uid = uid
        self.modelUID = modelUID
        self.name = name
    }
}

/// How confidently two identities refer to the same physical device. Lower is better.
public enum MatchTier: Int, Comparable, Sendable, CaseIterable {
    case uid = 0
    case modelAndName = 1
    case model = 2
    case name = 3

    public static func < (lhs: MatchTier, rhs: MatchTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension DeviceIdentity {
    /// The strongest tier at which these two identities match, or `nil` if they don't.
    public func matchTier(against other: DeviceIdentity) -> MatchTier? {
        if uid == other.uid { return .uid }
        if let model = modelUID, let otherModel = other.modelUID, model == otherModel {
            return name == other.name ? .modelAndName : .model
        }
        if name == other.name { return .name }
        return nil
    }
}
