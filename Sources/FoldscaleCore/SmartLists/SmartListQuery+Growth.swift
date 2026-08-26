import Foundation

// MARK: - What grew

extension SmartListQuery {
    static let growthMinimumBytes: Int64 = 500_000_000
    static let growthGroups = ["Last week", "Last month", "Longer"]
    /// A folder is left out when a listed folder inside it explains this much of its growth.
    static let growthExplainedFraction = 0.8

    /// Directories that got at least 500 MB bigger since an earlier scan, bucketed
    /// by the first window in which they grew, ranked by growth. Needs a size history
    /// with at least one earlier day; otherwise the list is empty (and hidden).
    mutating func whatGrew() -> ([SmartListEntry], [String]) {
        guard let history, history.rootPath == context.rootPath else { return ([], Self.growthGroups) }
        let windows = growthWindows(history)
        guard !windows.isEmpty else { return ([], Self.growthGroups) }
        let current = SizeHistory.Snapshot.capture(tree, date: now)

        var candidates: [GrowthCandidate] = []
        for (path, bytes) in current.entries {
            for window in windows {
                let before = window.snapshot.entries[path]
                let growth = bytes - (before ?? 0)
                guard growth >= Self.growthMinimumBytes else { continue }
                candidates.append(
                    GrowthCandidate(
                        path: path, growth: growth, group: window.group, isNew: before == nil,
                        since: window.snapshot.date))
                break
            }
        }
        // Deepest first, so each folder is judged against the folders inside it that
        // were already kept.
        candidates.sort { $0.depth > $1.depth }
        var kept: [GrowthCandidate] = []
        for candidate in candidates {
            let explained = kept.contains { inner in
                inner.path.hasPrefix(candidate.path + "/")
                    && Double(inner.growth) >= Self.growthExplainedFraction * Double(candidate.growth)
            }
            if !explained { kept.append(candidate) }
        }

        var entries: [SmartListEntry] = []
        for item in kept {
            guard let node = tree.node(atPathComponents: item.path.split(separator: "/").map(String.init))
            else { continue }
            let since = DisplayFormat.shortDay(item.since)
            let note = item.isNew ? "new since \(since)" : "+\(Self.format(item.growth)) since \(since)"
            entries.append(
                SmartListEntry(
                    node: node, group: item.group, note: note, safety: .informational, sortBytes: item.growth)
            )
        }
        return (entries, Self.growthGroups)
    }

    /// The baselines to compare against, oldest last: a week ago (or the oldest
    /// earlier day while the history is young), a month ago, and the oldest snapshot
    /// when it predates the month baseline.
    private func growthWindows(_ history: SizeHistory) -> [(group: String, snapshot: SizeHistory.Snapshot)] {
        var windows: [(group: String, snapshot: SizeHistory.Snapshot)] = []
        let week = history.baseline(olderThan: 7 * 86_400, now: now) ?? history.oldestBefore(day: now)
        if let week { windows.append(("Last week", week)) }
        if let month = history.baseline(olderThan: 30 * 86_400, now: now), month.date != week?.date {
            windows.append(("Last month", month))
        }
        if let oldest = history.snapshots.first, let last = windows.last, oldest.date < last.snapshot.date {
            windows.append(("Longer", oldest))
        }
        return windows
    }

    private struct GrowthCandidate {
        let path: String
        let growth: Int64
        let group: String
        let isNew: Bool
        let since: Date
        var depth: Int { path.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "/") ? 1 : 0) } }
    }
}
