import Foundation

/// A small ledger of directory sizes over time, so "What grew" can compare today's
/// scan with earlier ones (ADR-0006). One history per scan root. Each snapshot keeps
/// only the directories that matter (a few levels deep, above a size floor, capped),
/// and old snapshots are thinned, so the file stays a few MB at most.
public struct SizeHistory: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public struct Snapshot: Codable, Sendable, Equatable {
        public static let defaultMaxDepth = 5
        public static let defaultMinimumBytes: Int64 = 50_000_000
        public static let defaultMaxEntries = 3000

        public let date: Date
        /// Root-relative, "/"-joined directory path → allocated bytes of that directory.
        public let entries: [String: Int64]

        public init(date: Date, entries: [String: Int64]) {
            self.date = date
            self.entries = entries
        }

        /// Directories down to `maxDepth` (1 = the root's children) of at least
        /// `minimumBytes`, keeping the `maxEntries` largest. A child never outweighs
        /// its parent, so stopping below the floor loses nothing.
        public static func capture(
            _ tree: FileTree, date: Date, maxDepth: Int = defaultMaxDepth,
            minimumBytes: Int64 = defaultMinimumBytes, maxEntries: Int = defaultMaxEntries
        ) -> Snapshot {
            var found: [(path: String, bytes: Int64)] = []
            func visit(_ node: FileTree.NodeID, path: String, depth: Int) {
                tree.forEachChild(of: node) { child in
                    guard tree.isDirectory(child) else { return }
                    let bytes = tree.totalAllocatedSize(of: child)
                    guard bytes >= minimumBytes else { return }
                    let name = tree.name(of: child)
                    let childPath = path.isEmpty ? name : path + "/" + name
                    found.append((childPath, bytes))
                    if depth < maxDepth { visit(child, path: childPath, depth: depth + 1) }
                }
            }
            visit(tree.rootID, path: "", depth: 1)
            if found.count > maxEntries {
                found.sort { $0.bytes > $1.bytes }
                found.removeLast(found.count - maxEntries)
            }
            return Snapshot(
                date: date,
                entries: Dictionary(
                    found.map { ($0.path, $0.bytes) }, uniquingKeysWith: { first, _ in first }))
        }
    }

    public static let recentWindow: TimeInterval = 14 * 86_400
    public static let thinnedSpacing: TimeInterval = 6 * 86_400
    public static let retention: TimeInterval = 90 * 86_400

    public let formatVersion: Int
    public let rootPath: String
    /// Oldest first.
    public private(set) var snapshots: [Snapshot]

    public init(rootPath: String, snapshots: [Snapshot] = []) {
        formatVersion = Self.currentFormatVersion
        self.rootPath = rootPath
        self.snapshots = snapshots.sorted { $0.date < $1.date }
    }

    /// Adds a snapshot, replacing one from the same calendar day, then thins the
    /// past relative to it: everything from the last 14 days stays, before that one
    /// snapshot per six days, nothing older than 90 days.
    public mutating func record(_ snapshot: Snapshot, calendar: Calendar = .current) {
        snapshots.removeAll { calendar.isDate($0.date, inSameDayAs: snapshot.date) }
        snapshots.append(snapshot)
        snapshots.sort { $0.date < $1.date }
        var kept: [Snapshot] = []
        for item in snapshots {
            let age = snapshot.date.timeIntervalSince(item.date)
            if age > Self.retention { continue }
            if age > Self.recentWindow, let previous = kept.last,
                item.date.timeIntervalSince(previous.date) < Self.thinnedSpacing
            {
                continue
            }
            kept.append(item)
        }
        snapshots = kept
    }

    /// The newest snapshot at least `seconds` older than `now`.
    public func baseline(olderThan seconds: TimeInterval, now: Date) -> Snapshot? {
        snapshots.last { now.timeIntervalSince($0.date) >= seconds }
    }

    /// The oldest snapshot not taken today — the fallback while the history is young.
    public func oldestBefore(day now: Date, calendar: Calendar = .current) -> Snapshot? {
        snapshots.first { !calendar.isDate($0.date, inSameDayAs: now) }
    }
}
