import Foundation

/// A device we know about, whether or not it is currently plugged in.
///
/// `id` is ours and never changes, so everything else (toggle pair, recents) references devices
/// by `id` rather than by any Core Audio value that might churn.
public struct DeviceRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var identity: DeviceIdentity
    public var alias: String?
    public var isHidden: Bool
    /// An SF Symbol name chosen by the user. `nil` means "work it out from the hardware".
    public var symbolName: String?

    public init(id: UUID = UUID(),
                identity: DeviceIdentity,
                alias: String? = nil,
                isHidden: Bool = false,
                symbolName: String? = nil) {
        self.id = id
        self.identity = identity
        self.alias = alias
        self.isHidden = isHidden
        self.symbolName = symbolName
    }

    /// What the user sees. An alias always wins over the hardware name.
    public var displayName: String {
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? identity.name : trimmed
    }
}

public enum ToggleMode: String, Codable, Sendable {
    /// Left click always flips between the two pinned devices.
    case pinnedPair
    /// Left click returns to the most recently used other device.
    case mostRecentlyUsed
}

public struct Settings: Codable, Equatable, Sendable {
    /// Known devices, in the order they should appear in the menu.
    public var devices: [DeviceRecord]
    public var toggleMode: ToggleMode
    /// The two halves of the pinned pair. Only used when `toggleMode == .pinnedPair`, and only
    /// when both are set — a half-configured pair falls back to most-recently-used.
    public var pinnedFirst: UUID?
    public var pinnedSecond: UUID?
    /// Most recently used first, capped at `recentsLimit`.
    public var recents: [UUID]
    /// A system-wide key that does the same as a left click. `nil` means no shortcut.
    public var hotKey: HotKey?

    public static let recentsLimit = 10

    public init(devices: [DeviceRecord] = [],
                toggleMode: ToggleMode = .pinnedPair,
                pinnedFirst: UUID? = nil,
                pinnedSecond: UUID? = nil,
                recents: [UUID] = [],
                hotKey: HotKey? = nil) {
        self.devices = devices
        self.toggleMode = toggleMode
        self.pinnedFirst = pinnedFirst
        self.pinnedSecond = pinnedSecond
        self.recents = recents
        self.hotKey = hotKey
    }

    /// The pair, but only when it is complete and refers to two different devices.
    public var pinnedPair: [UUID] {
        guard let pinnedFirst, let pinnedSecond, pinnedFirst != pinnedSecond else { return [] }
        return [pinnedFirst, pinnedSecond]
    }

    public func record(id: UUID) -> DeviceRecord? {
        devices.first { $0.id == id }
    }

    /// Moves `id` to the front of the recents list.
    public func recordingUse(of id: UUID) -> Settings {
        var copy = self
        copy.recents.removeAll { $0 == id }
        copy.recents.insert(id, at: 0)
        copy.recents = Array(copy.recents.prefix(Settings.recentsLimit))
        return copy
    }

    /// Drops recents and pins that no longer refer to a known device.
    public func prunedReferences() -> Settings {
        let known = Set(devices.map(\.id))
        var copy = self
        copy.recents = copy.recents.filter(known.contains)
        if let first = copy.pinnedFirst, !known.contains(first) { copy.pinnedFirst = nil }
        if let second = copy.pinnedSecond, !known.contains(second) { copy.pinnedSecond = nil }
        return copy
    }
}
