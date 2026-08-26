import Foundation

/// One reclaimable candidate in the "Free up space" flow.
public struct SpaceSuggestion: Sendable, Equatable, Identifiable {
    public var id: FileTree.NodeID { node }
    public let node: FileTree.NodeID
    /// The list it came from.
    public let source: SmartListKind
    public let group: String
    public let safety: SmartListSafety
    public let note: String?
    /// Bytes reclaimed by trashing it (the node's size; support data isn't trashed).
    public let bytes: Int64
    /// Ranking bucket: lower comes first. Safe items precede review-first ones;
    /// within a tier, the more disposable kinds come first.
    public let priority: Int

    public init(
        node: FileTree.NodeID, source: SmartListKind, group: String, safety: SmartListSafety,
        note: String?, bytes: Int64, priority: Int
    ) {
        self.node = node
        self.source = source
        self.group = group
        self.safety = safety
        self.note = note
        self.bytes = bytes
        self.priority = priority
    }
}

/// Turns the smart lists into a ranked "what can go" plan for a target amount.
/// Pure and Foundation-only, so the ranking and the greedy pick are unit-tested.
public enum FreeUpPlanner {
    /// Quick-pick targets, in bytes (5 · 10 · 25 · 50 · 100 GB).
    public static let quickTargets: [Int64] = [5, 10, 25, 50, 100].map { $0 * 1_000_000_000 }

    /// Candidates from every list, informational rows excluded, one per node. When
    /// two lists disagree about an item, the **more cautious** classification wins
    /// (a folder that one list calls a cache and another calls a project is treated
    /// as a project); priority only breaks ties within the same safety.
    public static func suggestions(
        from lists: [SmartListKind: SmartListResult], in tree: FileTree
    ) -> [SpaceSuggestion] {
        var best: [FileTree.NodeID: SpaceSuggestion] = [:]
        for (kind, result) in lists {
            for entry in result.entries where entry.safety != .informational && tree.isLive(entry.node) {
                let candidate = SpaceSuggestion(
                    node: entry.node, source: kind, group: entry.group, safety: entry.safety,
                    note: entry.note,
                    bytes: tree.totalAllocatedSize(of: entry.node),
                    priority: priority(kind, entry.group, entry.safety))
                if let existing = best[entry.node], !prefers(candidate, over: existing) { continue }
                best[entry.node] = candidate
            }
        }
        return best.values.sorted { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.bytes > rhs.bytes
        }
    }

    private static func prefers(_ candidate: SpaceSuggestion, over existing: SpaceSuggestion) -> Bool {
        let candidateCaution = caution(candidate.safety)
        let existingCaution = caution(existing.safety)
        if candidateCaution != existingCaution { return candidateCaution > existingCaution }
        return candidate.priority < existing.priority
    }

    private static func caution(_ safety: SmartListSafety) -> Int {
        switch safety {
        case .safeToTrash: return 0
        case .reviewFirst: return 1
        case .informational: return 2
        }
    }

    /// Picks suggestions in rank order until `target` bytes are covered. A pick
    /// nested under an earlier pick is skipped, and picking a folder evicts any
    /// earlier picks inside it, so the running total always equals
    /// ``reclaimTotal(of:in:)`` and no redundant rows are ticked. Only safe items
    /// are picked automatically unless `includeReviewFirst` is set.
    public static func greedySelection(
        target: Int64, from suggestions: [SpaceSuggestion], in tree: FileTree,
        includeReviewFirst: Bool = false
    ) -> Set<FileTree.NodeID> {
        var picked = Set<FileTree.NodeID>()
        var total: Int64 = 0
        for suggestion in suggestions where total < target {
            guard includeReviewFirst || suggestion.safety == .safeToTrash else { continue }
            guard !hasAncestor(of: suggestion.node, in: picked, tree: tree) else { continue }
            for nested in picked where hasAncestor(of: nested, in: [suggestion.node], tree: tree) {
                picked.remove(nested)
                total -= tree.totalAllocatedSize(of: nested)
            }
            picked.insert(suggestion.node)
            total += suggestion.bytes
        }
        return picked
    }

    /// Bytes reclaimed by trashing `selected`, counting a nested item only once
    /// (trashing a folder takes its contents with it).
    public static func reclaimTotal(of selected: Set<FileTree.NodeID>, in tree: FileTree) -> Int64 {
        selected.reduce(Int64(0)) { sum, node in
            hasAncestor(of: node, in: selected, tree: tree) ? sum : sum + tree.totalAllocatedSize(of: node)
        }
    }

    /// The outermost members of `selected` — what actually needs trashing.
    public static func outermost(of selected: Set<FileTree.NodeID>, in tree: FileTree) -> Set<FileTree.NodeID>
    {
        selected.filter { !hasAncestor(of: $0, in: selected, tree: tree) }
    }

    /// Whether any ancestor of `node` is in `set`.
    public static func hasAncestor(
        of node: FileTree.NodeID, in set: Set<FileTree.NodeID>, tree: FileTree
    ) -> Bool {
        var current = tree.parent(of: node)
        while current != FileTree.none {
            if set.contains(current) { return true }
            current = tree.parent(of: current)
        }
        return false
    }

    /// Safe tiers first (0–9), then review-first (10+); within a tier, the more
    /// disposable the better.
    static func priority(_ kind: SmartListKind, _ group: String, _ safety: SmartListSafety) -> Int {
        switch safety {
        case .safeToTrash: return safePriority(kind, group)
        case .reviewFirst: return 10 + reviewPriority(kind, group)
        case .informational: return 99
        }
    }

    private static func safePriority(_ kind: SmartListKind, _ group: String) -> Int {
        switch kind {
        case .developerJunk: return group == "Build output" ? 0 : 1
        case .cachesAndTrash: return 2
        case .downloads: return group == "Installers & archives" ? 3 : 4
        case .appsAndGames, .bigProjects, .videos, .phoneBackups, .virtualMachines, .whatGrew: return 5
        }
    }

    /// Review-first order: forgotten downloads first, then recordings, projects,
    /// other videos, phone backups, games, apps, virtual machines.
    private static func reviewPriority(_ kind: SmartListKind, _ group: String) -> Int {
        switch kind {
        case .downloads: return 0
        case .videos: return group == "Recordings" ? 2 : 4
        case .bigProjects: return 3
        case .phoneBackups: return 5
        case .appsAndGames: return group == "Games" ? 6 : 7
        case .virtualMachines: return 8
        case .cachesAndTrash, .developerJunk, .whatGrew: return 9
        }
    }
}
