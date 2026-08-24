import Foundation

/// A single request to trash one item, with the allocated bytes it will reclaim.
public struct TrashItem: Sendable, Equatable {
    public let url: URL
    public let allocatedBytes: Int64

    public init(url: URL, allocatedBytes: Int64) {
        self.url = url
        self.allocatedBytes = allocatedBytes
    }
}

/// One item that could not be trashed.
public struct TrashFailure: Sendable {
    public let url: URL
    public let message: String
}

/// The result of a trash operation.
public struct TrashOutcome: Sendable {
    /// Original URLs successfully moved to the Trash.
    public var trashed: [URL] = []
    /// The corresponding new locations inside the Trash (for a future Undo).
    public var trashedLocations: [URL] = []
    /// URLs refused because they are protected (handoff §6).
    public var refused: [URL] = []
    /// URLs that errored during trashing.
    public var failed: [TrashFailure] = []
    /// Total allocated bytes reclaimed by the successful moves.
    public var reclaimedBytes: Int64 = 0

    public init() {}

    public var isEmpty: Bool { trashed.isEmpty && refused.isEmpty && failed.isEmpty }
}

/// Moves files to the system Trash. **The only path to deletion in Radix** — it
/// uses `FileManager.trashItem` exclusively (never `removeItem`, per handoff §6),
/// and refuses protected items before touching them.
public enum TrashService {
    /// Moves each item to the Trash unless `isProtected` returns true for it.
    /// Foundation-only and synchronous; callers run it off the main actor.
    public static func moveToTrash(
        _ items: [TrashItem],
        isProtected: (URL) -> Bool
    ) -> TrashOutcome {
        var outcome = TrashOutcome()
        let fileManager = FileManager.default
        for item in items {
            if isProtected(item.url) {
                outcome.refused.append(item.url)
                continue
            }
            var resulting: NSURL?
            do {
                try fileManager.trashItem(at: item.url, resultingItemURL: &resulting)
                outcome.trashed.append(item.url)
                if let location = resulting as URL? { outcome.trashedLocations.append(location) }
                outcome.reclaimedBytes += item.allocatedBytes
            } catch {
                outcome.failed.append(
                    TrashFailure(url: item.url, message: error.localizedDescription))
            }
        }
        return outcome
    }
}
