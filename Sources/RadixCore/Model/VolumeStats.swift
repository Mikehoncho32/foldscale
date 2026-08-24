import Foundation

/// Capacity figures for the volume containing a path, for the footer (handoff §4,
/// rule 6) and the APFS purgeable-space explanation (§5.11).
///
/// - `availableCapacity` is the conservative "true free" number.
/// - `availableForImportantUsage` is free **plus** purgeable (caches, evictable
///   cloud files, snapshots macOS can reclaim on demand) — usually the larger
///   figure Finder shows. The difference is surfaced as ``purgeable`` so the UI
///   can explain why the numbers differ.
public struct VolumeStats: Sendable, Equatable {
    public var totalCapacity: Int64
    public var availableCapacity: Int64
    public var availableForImportantUsage: Int64

    public init(totalCapacity: Int64, availableCapacity: Int64, availableForImportantUsage: Int64) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.availableForImportantUsage = availableForImportantUsage
    }

    /// Space in use = total − true free.
    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }

    /// Reclaimable-on-demand space = important-usage free − true free.
    public var purgeable: Int64 { max(0, availableForImportantUsage - availableCapacity) }

    /// Reads capacity for the volume containing `url`; `nil` if unavailable.
    public static func forVolume(containing url: URL) -> VolumeStats? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return VolumeStats(
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
