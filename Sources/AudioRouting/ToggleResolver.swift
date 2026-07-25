import Foundation

/// Decides what a left click should switch to.
///
/// Rules, in order:
/// 1. Pinned pair (when configured): flip to the other half. If the current device is outside
///    the pair, jump into it. A pinned device is honoured even if it is hidden from the menu.
/// 2. Most recently used device that is still connected and not hidden.
/// 3. Cycle to the next connected, non-hidden device in menu order.
///
/// Returns `nil` when there is nowhere sensible to go (e.g. only one device is connected).
public enum ToggleResolver {
    public static func target(settings: Settings, devices: [ResolvedDevice]) -> ResolvedDevice? {
        let current = devices.first(where: \.isCurrent)

        if settings.toggleMode == .pinnedPair, settings.pinnedPair.count == 2 {
            let pair = settings.pinnedPair.compactMap { id in devices.first { $0.record.id == id } }
            if pair.count == 2 {
                if current?.id == pair[0].id, pair[1].isOnline { return pair[1] }
                if current?.id == pair[1].id, pair[0].isOnline { return pair[0] }
                if current?.id != pair[0].id, current?.id != pair[1].id,
                   let entry = pair.first(where: \.isOnline) {
                    return entry
                }
            }
        }

        for id in settings.recents where id != current?.id {
            if let candidate = devices.first(where: { $0.id == id }),
               candidate.isOnline, !candidate.record.isHidden {
                return candidate
            }
        }

        let cycle = devices.filter { $0.isOnline && !$0.record.isHidden }
        guard !cycle.isEmpty else { return nil }
        if let current, let index = cycle.firstIndex(where: { $0.id == current.id }) {
            guard cycle.count > 1 else { return nil }
            return cycle[(index + 1) % cycle.count]
        }
        return cycle.first
    }
}
