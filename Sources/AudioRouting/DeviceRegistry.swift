import Foundation

/// A known device paired with its live state, if it is currently connected.
public struct ResolvedDevice: Equatable, Sendable, Identifiable {
    public var record: DeviceRecord
    public var device: AudioOutputDevice?
    public var isCurrent: Bool

    public var id: UUID { record.id }
    public var isOnline: Bool { device != nil }
    public var displayName: String { record.displayName }

    public init(record: DeviceRecord, device: AudioOutputDevice?, isCurrent: Bool) {
        self.record = record
        self.device = device
        self.isCurrent = isCurrent
    }
}

/// Reconciles saved settings against the devices the system currently reports.
///
/// Records are never dropped when a device disconnects, so aliases, hidden flags and the toggle
/// pair survive unplugging. When a device comes back with a different UID (see `DeviceIdentity`)
/// it is matched on the strongest available key and the stored identity is refreshed in place.
public enum DeviceRegistry {
    public struct Reconciliation: Equatable, Sendable {
        public var settings: Settings
        public var devices: [ResolvedDevice]

        public init(settings: Settings, devices: [ResolvedDevice]) {
            self.settings = settings
            self.devices = devices
        }

        /// Devices that belong in the menu: known, connected and not hidden.
        public var menuDevices: [ResolvedDevice] {
            devices.filter { $0.isOnline && !$0.record.isHidden }
        }

        public var current: ResolvedDevice? {
            devices.first(where: \.isCurrent)
        }
    }

    public static func reconcile(settings: Settings,
                                 live: [AudioOutputDevice],
                                 current: AudioOutputDevice?) -> Reconciliation {
        var records = settings.devices
        var liveByRecord = [Int: Int]()
        var claimedLive = Set<Int>()

        // Match strongest key first so a weak name match can never steal a device that a
        // different record would have matched by UID.
        for tier in MatchTier.allCases.sorted() {
            for (recordIndex, record) in records.enumerated() where liveByRecord[recordIndex] == nil {
                let match = live.indices.first { liveIndex in
                    !claimedLive.contains(liveIndex)
                        && record.identity.matchTier(against: live[liveIndex].identity) == tier
                }
                if let match {
                    liveByRecord[recordIndex] = match
                    claimedLive.insert(match)
                }
            }
        }

        // Absorb identity churn into the records we already have.
        for (recordIndex, liveIndex) in liveByRecord {
            records[recordIndex].identity = live[liveIndex].identity
        }

        // Anything left over is a device we've never seen before.
        var newRecords: [DeviceRecord] = []
        for (liveIndex, device) in live.enumerated() where !claimedLive.contains(liveIndex) {
            let record = DeviceRecord(identity: device.identity)
            newRecords.append(record)
            liveByRecord[records.count + newRecords.count - 1] = liveIndex
        }
        records.append(contentsOf: newRecords)

        let resolved = records.enumerated().map { index, record in
            let device = liveByRecord[index].map { live[$0] }
            let isCurrent = device != nil && device?.objectID == current?.objectID
            return ResolvedDevice(record: record, device: device, isCurrent: isCurrent)
        }

        var updated = settings
        updated.devices = records
        return Reconciliation(settings: updated.prunedReferences(), devices: resolved)
    }
}
